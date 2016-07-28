use strict;
use warnings;

use constant _CONSUMER_KEY => 'w4mCATjlzalDgmnEmVMAfk78R';
use constant _CALLBACK_URL => 'https://www.edentest.com/oauth/foo';

use constant _CONSUMER_SECRET => sub {
	my $secret = `cat /home/ec2-user/consumer_secret.txt`;
	chomp($secret);
	return $secret;
}->();

use Plack::Request;
use Plack::Builder;
use Plack::App::URLMap;
use Net::Twitter;

my $appoauth = sub {
	my $env = shift;

	my $req = Plack::Request->new($env);

	my $verifier = $req->parameters->{oauth_verifier};
	my $oauth_token = $req->parameters->{oauth_token};

	unless ($verifier) {
		return [
			200,
			['Content-Type' => 'text/html'],
			["I guess we're stuck then, if you won't approve."],
		];
	}

	my $session = $env->{'psgix.session'};
	my $request_token = $session->{request_token} or die 'no request token in session';
	my $request_token_secret = $session->{request_token_secret} or die 'no request token secret in session';

	if ($oauth_token ne $request_token) {
		require Data::Dumper;
		die sprintf('the oauth token [%s] versus request token [%s] . . . [%s]', $oauth_token, $request_token, Data::Dumper::Dumper($req));
	}

	my $client = Net::Twitter->new(
		traits => [qw(
			API::RESTv1_1
			OAuth
		)],
		consumer_key	=> _CONSUMER_KEY(),
		consumer_secret	=> _CONSUMER_SECRET(),
	);

	$client->request_token($request_token);
	$client->request_token_secret($request_token_secret);

	my ($access_token, $access_token_secret) = $client->request_access_token(verifier => $verifier);

	die 'no access token' unless $client->access_token;
	die 'no access token secret' unless $client->access_token_secret;

	$client->update({ status => _get_sentence() });

	return [
		200,
		['Content-Type' => 'text/html'],
		['and we posted . . . '],
	];
};

sub _get_sentence {
	my $txt = `cat /home/ec2-user/whale.txt`;
	my @txt = split(/[.]/, $txt);
	@txt = grep { $_ !~ /[<>]/ } @txt;
	my $rv = $txt[int(rand(scalar(@txt)))];
	chomp($rv);
	($rv) = $rv =~ m/\s*([^\s].+)/;
	return substr($rv, 0, 140); # twitter api doesn't accept more than 140 chars
}

# just print a link to the twitter authorization page - the link incorporates our consumer secret and consumer key, along with our specified callback url
my $appindex = sub {
	my $env = shift;

	my $req = Plack::Request->new($env);
	my $res = $req->new_response(200);

	my $htmltemplate = `cat /home/ec2-user/pageprintftemplate.html`;

	$res->content_type('text/html');

	my $client = Net::Twitter->new(
		traits => [qw(
			API::RESTv1_1
			OAuth
		)],
		consumer_key	=> _CONSUMER_KEY(),
		consumer_secret	=> _CONSUMER_SECRET(),
	);

	my $authorization_url = $client->get_authorization_url(
		callback => _CALLBACK_URL(),
	);

	my $request_token = $client->request_token or die 'no request token';
	my $request_token_secret = $client->request_token_secret or die 'no request_token_secret';

	my $session = $env->{'psgix.session'};

	$session->{request_token} = $request_token;
	$session->{request_token_secret} = $request_token_secret;

	$res->content(sprintf(
		$htmltemplate,
		$authorization_url,
	));

	return $res->finalize;
};

my $urlmap = Plack::App::URLMap->new;
$urlmap->mount("/"		=> $appindex);
$urlmap->mount("/oauth/"	=> $appoauth);
$urlmap->mount(
	"/health/"	=> sub {
		my $env = shift;
		my $req = Plack::Request->new($env);
		my $res = $req->new_response(200);
		$res->content("I'm not dead yet");
		return $res->finalize;
	},
);

builder {
	enable 'Session', store => 'File';
	$urlmap->to_app;
};



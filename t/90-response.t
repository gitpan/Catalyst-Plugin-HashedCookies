#!perl

use strict;
use warnings;

use Test::More tests => 8;

use lib 't/lib';
BEGIN { use_ok('Catalyst::Test', ('TestApp')); }

use HTTP::Headers::Util 'split_header_words';

{
    my $expected = { 
        Catalyst => [ qw( Catalyst Cool&Catalyst&_hashedcookies_digest&e6f93c203e5c47608ae7b89808a8386e5ebd2866 path / ) ],
    };

    ok( my $response = request('http://localhost/cookies/three'), 'Request' );
    ok( $response->is_success, 'Response Successful 2xx' );
    is( $response->content_type, 'text/plain', 'Response Content-Type' );
    is( $response->header( 'X-Catalyst-Action' ), 'cookies/three', 'Test Action' );

    my $cookies = {};

    for my $cookie ( split_header_words( $response->header('Set-Cookie') ) ) {
        $cookies->{ $cookie->[0] } = $cookie;
    }

    is_deeply( $cookies, $expected, 'Response Cookies' );
}

{
    ok( my $response = request('http://localhost/cookies/four'), 'Request' );
    is( $response->status_line, '500 Internal Server Error', 'Trapped reserved cookie value');
}

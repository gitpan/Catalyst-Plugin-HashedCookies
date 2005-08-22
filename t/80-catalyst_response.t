#!perl

use strict;
use warnings;

use Test::More tests => 11;

use lib 't/lib';
BEGIN { use_ok('Catalyst::Test', ('TestApp')); }

use HTTP::Headers::Util 'split_header_words';

my $expected = { 
    Catalyst => [ qw( Catalyst _hashedcookies_padding&Cool&_hashedcookies_digest&65e17e8e30702baa1e40080514d09d35a207ddc2 path / ) ],
    Cool     => [ qw( Cool _hashedcookies_padding&Catalyst&_hashedcookies_digest&ed7516dabdeff2e7f2c777a400680fe270cd9691 path / ) ]
};

{
    ok( my $response = request('http://localhost/cookies/one'), 'Request' );
    ok( $response->is_success, 'Response Successful 2xx' );
    is( $response->content_type, 'text/plain', 'Response Content-Type' );
    is( $response->header( 'X-Catalyst-Action' ), 'cookies/one', 'Test Action' );

    my $cookies = {};

    for my $cookie ( split_header_words( $response->header('Set-Cookie') ) ) {
        $cookies->{ $cookie->[0] } = $cookie;
    }

    is_deeply( $cookies, $expected, 'Response Cookies' );
}

{
    ok( my $response = request('http://localhost/cookies/two'), 'Request' );
    ok( $response->is_redirect, 'Response Redirection 3xx' );
    is( $response->code, 302, 'Response Code' );
    is( $response->header( 'X-Catalyst-Action' ), 'cookies/two', 'Test Action' );

    my $cookies = {};

    for my $cookie ( split_header_words( $response->header('Set-Cookie') ) ) {
        $cookies->{ $cookie->[0] } = $cookie;
    }

    is_deeply( $cookies, $expected, 'Response Cookies' );
}

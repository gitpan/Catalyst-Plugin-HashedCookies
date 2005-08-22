#!perl

use strict;
use warnings;

use Test::More tests => 10;

use lib 't/lib';
BEGIN { use_ok('Catalyst::Test', ('TestApp')); }

{
    ok( my $response = request('http://localhost/dump/request'), 'Request' );
    ok( $response->is_success, 'Response Successful 2xx' );
    is( $response->content_type, 'text/plain', 'Response Content-Type' );
    like( $response->content, qr/^bless\( .* 'Catalyst::Request' \)$/s, 'Content is a serialized Catalyst::Request' );

    is( $response->header('X-Catalyst-Plugins'), 'Catalyst::Plugin::HashedCookies', 'Loaded HashedCookies plugin' );

    my $creq;
    ok( eval '$creq = ' . $response->content, 'Unserialize Catalyst::Request' );
    isa_ok( $creq, 'Catalyst::Request' );

    # has installed two methods into $c->request
    can_ok( $creq, 'valid_cookie' );
    can_ok( $creq, 'invalid_cookie' );
}

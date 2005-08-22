#!perl

use strict;
use warnings FATAL => 'all';

use Test::More tests => 6;

use lib 't/lib';
BEGIN { use_ok('Catalyst::Test', ('BasicTestApp')); }

{
    ok( BasicTestApp->config->{hashedcookies}->{key} = 'abcdef0123456789ASDF', 'Set key to keep HC quiet' );
    is( BasicTestApp->setup(), 0, 'Configuration is sane, setup() goes well' );

    is( BasicTestApp->config->{hashedcookies}->{algorithm}, 'SHA1', 'Default algorithm is set' );

    ok( exists BasicTestApp->config->{hashedcookies}->{required}, 'Unspecified required is noticed' );
    is( BasicTestApp->config->{hashedcookies}->{required}, '1', 'Default required is set' );
}

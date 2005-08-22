#!perl

use strict;
use warnings FATAL => 'all';

use Test::More tests => 20;

use lib 't/lib';
BEGIN { use_ok('Catalyst::Test', ('BasicTestApp')); }

{
    undef BasicTestApp->config->{hashedcookies};
    is( eval{ BasicTestApp->setup() }, undef, 'Setup dies without a key' );

    ok( BasicTestApp->config->{hashedcookies}->{key} = 'abcdef0123456789ASDF', 'Set key to keep HashedCookies quiet' );
    is( BasicTestApp->setup(), 0, 'Setup is happy with only a key set' );

    is( BasicTestApp->config->{hashedcookies}->{key} = undef, undef, 'Unset key to make HashedCokies die' );
    is( eval{ BasicTestApp->setup() }, undef, 'Setup dies without a key (2)' );
}

{
    undef BasicTestApp->config->{hashedcookies};
    BasicTestApp->config->{hashedcookies}->{key} = 'abcdef0123456789ASDF';
    # we know default algorithm is set from t/10-basics.t

    ok( BasicTestApp->config->{hashedcookies}->{algorithm} = 'MD5', 'Set alternate algorithm' );
    undef *{Catalyst::Setup::_components};
    is( BasicTestApp->setup(), 0, 'Setup is happy with alternate algorithm' );
    is( BasicTestApp->config->{hashedcookies}->{algorithm}, 'MD5', 'Setup hasn\'t altered our algorithm' );

    is( BasicTestApp->config->{hashedcookies}->{algorithm} = undef, undef, 'Set algorithm to undef' );
    undef *{Catalyst::Setup::_components};
    is( BasicTestApp->setup(), 0, 'Setup copes with undef algorithm' );
    is( BasicTestApp->config->{hashedcookies}->{algorithm}, 'SHA1', 'Default algorithm is set' );

    is( BasicTestApp->config->{hashedcookies}->{algorithm} = '', '', 'Set algorithm to empty string' );
    undef *{Catalyst::Setup::_components};
    is( BasicTestApp->setup(), 0, 'Setup copes with empty string algorithm' );
    is( BasicTestApp->config->{hashedcookies}->{algorithm}, 'SHA1', 'Default algorithm is set' );

    ok( BasicTestApp->config->{hashedcookies}->{algorithm} = 'OLIVER', 'Set unkown algorithm' );
    undef *{Catalyst::Setup::_components};
    is( eval{ BasicTestApp->setup() }, undef, 'Setup dies on unkown algorithm' );
}

{
    undef BasicTestApp->config->{hashedcookies};
    undef *{Catalyst::Setup::_components};
    BasicTestApp->config->{hashedcookies}->{key} = 'abcdef0123456789ASDF';
    # we know unspecified required is noticed and set from t/10-basics.t

    is( BasicTestApp->config->{hashedcookies}->{required} = undef, undef, 'Set required to undef' );
    is( BasicTestApp->setup(), 0, 'Setup is happy with undef required' );
    is( BasicTestApp->config->{hashedcookies}->{required}, undef, 'Setup hasn\'t altered required' );
}

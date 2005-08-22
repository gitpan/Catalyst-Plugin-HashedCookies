#!perl -Tw

use Test::More tests => 1;

BEGIN {
	use_ok( 'Catalyst::Plugin::HashedCookies' );
}

diag( "Testing Catalyst::Plugin::HashedCookies $Catalyst::Plugin::HashedCookies::VERSION, Perl $], $^X" );

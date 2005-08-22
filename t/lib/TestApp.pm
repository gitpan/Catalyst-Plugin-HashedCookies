package TestApp;

use strict;
use warnings FATAL => 'all';
our $VERSION = 0.01;

use Catalyst qw[-Engine=Test HashedCookies];
use File::Spec::Functions qw[catpath splitpath rel2abs];
use Data::Dumper;

__PACKAGE__->config(
    name => 'TestApp',
    root => rel2abs( catpath( ( splitpath($0) )[0,1], '' ) ),
    hashedcookies => { key => 'abcdef0123456789ASDF' },
);
__PACKAGE__->setup();

sub default : Private {
    my ($self, $c) = @_;
    $c->forward('TestApp::View::Dump::Request');
    {
        no strict 'refs';
        my $plugins = join( ', ', sort grep { m/^Catalyst::Plugin/ } @{ (ref $c) . '::ISA' } );
        $c->response->header( 'X-Catalyst-Plugins' => $plugins );
    }
}

1;

package TestApp::Controller::Cookies;

use strict;
use base 'Catalyst::Base';

sub one : Relative {
    my ( $self, $c ) = @_;
    $c->res->cookies->{Catalyst} = { value => 'Cool',     path => '/' };
    $c->res->cookies->{Cool}     = { value => 'Catalyst', path => '/' };
    $c->res->header( 'X-Catalyst-Action' => $c->req->action );
    $c->forward('TestApp::View::Dump::Request');
}

sub two : Relative {
    my ( $self, $c ) = @_;
    $c->res->cookies->{Catalyst} = { value => 'Cool',     path => '/' };
    $c->res->cookies->{Cool}     = { value => 'Catalyst', path => '/' };
    $c->res->header( 'X-Catalyst-Action' => $c->req->action );
    $c->res->redirect('http://www.google.com/');
}

sub three : Relative {
    my ( $self, $c ) = @_;
    $c->res->cookies->{Catalyst} = { value => {'Cool' => 'Catalyst'},     path => '/' };
    $c->res->header( 'X-Catalyst-Action' => $c->req->action );
    $c->forward('TestApp::View::Dump::Request');
}

sub four : Relative {
    my ( $self, $c ) = @_;
    $c->res->cookies->{Cool} = { value => {'Catalyst' => '_hashedcookies_'},     path => '/' };
    $c->res->header( 'X-Catalyst-Action' => $c->req->action );
    $c->forward('TestApp::View::Dump::Request');
}

1;

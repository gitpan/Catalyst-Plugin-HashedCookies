package Catalyst::Plugin::HashedCookies;

use strict;
use warnings FATAL => 'all';

use Carp;
use NEXT;
use Tie::IxHash;
use CGI::Cookie;
use Digest::HMAC_MD5;
use Digest::HMAC_SHA1;
our $VERSION = 0.01;

=head1 NAME

Catalyst::Plugin::HashedCookies - Tamper-resistant HTTP Cookies

=head1 VERSION

This document refers to version 0.01 of Catalyst::Plugin::HashedCookies,
released Saturday August 20, 2005.

=head1 SYNOPSIS

 use Catalyst qw/HashedCookies/;

 MyApp->config->{hashedcookies} = {
     key       => $secret_key,
     algorithm => 'SHA1', # optional
     required  => 1,      # optional
 };

 # later, in another part of MyApp...

 print "this cookie tastes good!\n"
  if $c->request->valid_cookie('my_cookie_name');

=head1 DESCRIPTION

=head2 Overview

When HTTP cookies are used to store a user's state or identity it's
important that your application is able to distinguish legitimate
cookies from those that have been edited or created by a malicious
user.

This module allows you to determine whether a cookie presented by a
client was created in its current state by your own application.

=head2 Implementation

HashedCookies adds a keyed cryptographic hash to each cookie that your
application creates, and checks every client-provided cookie for a
valid hash.

This is done in a transparent way such that you do not need to change
B<any> application code that handles cookies when using this plugin. A
cookie that fails to contain a valid hash will still be available to
your application through C<$c->request->cookie()>.

Two additional methods within the Catalyst request object allow you to
check the status of your cookies' hashes.

=cut

{
=head2 Request Object Methods

=over 4

=cut

    package Catalyst::Request;
    use base qw/Class::Accessor::Fast/;
    __PACKAGE__->mk_accessors(qw/validhashedcookies invalidhashedcookies/);

=item valid_cookie($cookie_name)

If a cookie was successfully authenticated then this method will
return True, otherwise it will return False.

=cut

    # reveal whether a hashed cookie passed its integrity check
    sub valid_cookie {
      my $self = shift;
      my $name = shift;
    
      return exists $self->validhashedcookies->{$name};
    }
    
=item invalid_cookie($cookie_name)

If a cookie failed its authentication, then this method will return
True, otherwise it will return False. Please read the sections below
to understand what 'failed authentication' really means.

=back

=cut

    # reveal whether a hashed cookie passed its integrity check
    sub invalid_cookie {
      my $self = shift;
      my $name = shift;
    
      return exists $self->invalidhashedcookies->{$name};
    }
}

=head1 CONFIGURATION

=over 4

=item key

 MyApp->config->{hashedcookies} = {key => $secret_key};

This parameter is B<required>, and sets the secret key that is used to
generate a message authentication hash. Clearly, for a returned cookie
to be authenticated the same key must be used both when setting the
cookie and retrieving it.

=item algorithm

 MyApp->config->{hashedcookies} = {algorithm => 'SHA1'};
   # or
 MyApp->config->{hashedcookies} = {algorithm => 'MD5'};

This parameter is optional, and will default to C<SHA1> if not set. It
instructs the module to use the given message digest algorithm.

=item required

 MyApp->config->{hashedcookies} = {required => 0};
   # or
 MyApp->config->{hashedcookies} = {required => 1};

This parameter is optional, and will default to C<1> if not set.

When HashedCookies is reading the HTTP Cookies provided by a client, it
records whether the authentication succeeded or failed.
If a cookie is read from the client but does not contain a
HashedCookies hash (i.e. this module was not running when the cookie
was set), then this parameter controls whether the cookie is ignored.

Setting this parameter to True means that a cookie without a hash
is treated as if it did have a hash, and therefore the authentication
will fail. Setting this parameter to False means that the cookie will
be ignored.

When a cookie is ignored, neither C<$c->request->valid_cookie()> nor
C<$c->request->invalid_cookie()> will return True, but you can of
course still access the cookie through C<$c->request->cookie()>.

=back

=cut

sub setup {
  my $self = shift;

  $self->config->{hashedcookies}->{algorithm} ||= 'SHA1';
  ($self->config->{hashedcookies}->{algorithm} =~ m/^(?:SHA1|MD5)$/)
    or croak 'Use of unknown message digest algorithm';

  exists $self->config->{hashedcookies}->{required}
    or $self->config->{hashedcookies}->{required} = 1;
    # not checked - perl's handling of truth will make junk values 'work'

  defined $self->config->{hashedcookies}->{key}
    or croak '"key" is a required configuration parameter to '. __PACKAGE__;

  return $self->NEXT::setup(@_);
}

# remove and check hash in Cookie Values
sub prepare_cookies {
  my $c = shift;
  $c->NEXT::prepare_cookies( @_ );
  $c->request->validhashedcookies({});
  $c->request->invalidhashedcookies({});

  my $hasher = 'Digest::HMAC_'. $c->config->{hashedcookies}->{algorithm};
  my $hmac = $hasher->new( $c->config->{hashedcookies}->{key} );

  while ( my ( $name, $cgicookie ) = each %{ $c->request->cookies } ) {
    my @values = @{[$cgicookie->value]};
    my $digest = '';

    # restore cookie to original Value set by user
    if (scalar @values % 2 == 0) {
      my $t = Tie::IxHash->new(@values);
      my $d = $t->Indices('_hashedcookies_digest');
      my $p = $t->Indices('_hashedcookies_padding');

      if (defined $d) {
        $digest = $t->Values($d);
        splice(@values, $d * 2, 2);
      }

      if (defined $p) {
        splice(@values, $p * 2, 1);
      }

      $cgicookie->value(\@values);
    }

    my $required = $c->config->{hashedcookies}->{required};
    if (not $digest and not $required) {
      $c->log->debug( "HashedCookies skipping cookie:      $name" )
        if $c->debug;
      $hmac->reset;
      next;
    }
    # now, we either have no digest but one is required,
    # or we have a digest that needs checking

    $hmac->add($cgicookie->as_string);
    my $result = $hmac->hexdigest; # WARNING!!! $hmac has now been RESET

    # $c->log->debug( "HashedCookies retrieved digest: '$digest'" )
    #   if $c->debug;
    # $c->log->debug( "HashedCookies generated digest: '$result'" )
    #   if $c->debug;

    if ($digest eq $result) {
      $c->log->debug( "HashedCookies adding valid cookie:  $name" )
        if $c->debug;
      ++$c->request->validhashedcookies->{$name};
    } else {
      $c->log->debug( "HashedCookies found INVALID cookie: $name" )
        if $c->debug;
      ++$c->request->invalidhashedcookies->{$name};
    }

    $hmac->reset;
  }

  return $c;
}

# alter all Cookie Values to include a hash
sub finalize_cookies {
  my $c = shift;

  my $hasher = 'Digest::HMAC_'. $c->config->{hashedcookies}->{algorithm};
  my $hmac = $hasher->new( $c->config->{hashedcookies}->{key} );

  while ( my ( $name, $cookie ) = each %{ $c->response->cookies } ) {
    # creating a tmp CGI::Cookie is handy for as_string,
    # and also because we can consistenly use ->value as a list

    # only -name and -value are used because this is what CGI::Cookie->parse()
    # will pass back from an HTTP header - prepare_cookies needs identical hash
    my $cgicookie = CGI::Cookie->new(
      -name    => $name,
      -value   => $cookie->{value},
    );

    if (scalar grep /^_hashedcookies_(?:padding|digest)$/, @{[$cgicookie->value]}) {
      croak 'Attempted use of restricted ("_hashedcookies_*") value in cookie';
    }

    $hmac->add($cgicookie->as_string);

    # make sure that cookie ->value can be coerced into a hash upon retrieval
    if (scalar @{[$cgicookie->value]} % 2 == 1) {
      $cookie->{value} = [
        '_hashedcookies_padding' => @{[$cgicookie->value]},
        '_hashedcookies_digest'  => $hmac->hexdigest,
      ];
    } else {
      $cookie->{value} = [
        @{[$cgicookie->value]},
        '_hashedcookies_digest' => $hmac->hexdigest,
      ];
    }

    $hmac->reset;
  }

  $c->NEXT::finalize_cookies( @_ );
  return $c;
}

=head1 TODO

=over 4

=item *

More tests are definitely necessary; this is the first release, though.

=item *

Fix dependencies on Digest:: to allow only SHA1 or MD5 rather than both.

=back

=head1 SEE ALSO

L<Catalyst>, L<Digest::HMAC_SHA1>, L<Digest::HMAC_MD5>

L<http://www.schneier.com/blog/archives/2005/08/new_cryptanalyt.html>

=head1 AUTHOR

Oliver Gorwits C<< <oliver.gorwits@oucs.ox.ac.uk> >>

=head1 BUGS

Please report any bugs or feature requests to
C<bug-catalyst-plugin-hashedcookies@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Catalyst-Plugin-HashedCookies>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 ACKNOWLEDGEMENTS

All the helpful people in #catalyst.

=head1 COPYRIGHT & LICENSE

Copyright (c) 2005, Oliver Gorwits and The University of Oxford.
All Rights Reserved. This module is free software. It may be used,
redistributed and/or modified under the same terms as Perl itself.

=cut

1;

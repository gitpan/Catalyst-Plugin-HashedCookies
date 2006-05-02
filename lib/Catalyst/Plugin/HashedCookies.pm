package Catalyst::Plugin::HashedCookies;

use strict;
use warnings FATAL => 'all';

use NEXT;
use Symbol;
use Tie::IxHash;
use CGI::Cookie;
use Digest::HMAC_MD5;
use Digest::HMAC_SHA1;
use Class::Accessor::Fast;
our $VERSION = 0.03;

# apparently this should be done by subclassing Catalyst::Request and using
# response_class, but I'm suspicious that that process isn't tolerant to
# multiple users.

*{Symbol::qualify_to_ref('validhashedcookies', 'Catalyst::Request')} =
  Class::Accessor::Fast::make_accessor('Catalyst::Request', 'validhashedcookies');
*{Symbol::qualify_to_ref('invalidhashedcookies', 'Catalyst::Request')} =
  Class::Accessor::Fast::make_accessor('Catalyst::Request', 'invalidhashedcookies');


# reveal whether a hashed cookie passed its integrity check
*{Symbol::qualify_to_ref('valid_cookie', 'Catalyst::Request')} = sub {
    my $self = shift;
    my $name = shift;

    return exists $self->validhashedcookies->{$name};
};

# reveal whether a hashed cookie passed its integrity check
*{Symbol::qualify_to_ref('invalid_cookie', 'Catalyst::Request')} = sub {
    my $self = shift;
    my $name = shift;

    return exists $self->invalidhashedcookies->{$name};
};


sub setup {
    my $self = shift;

    $self->config->{hashedcookies}->{algorithm} ||= 'SHA1';
    ( $self->config->{hashedcookies}->{algorithm} =~ m/^(?:SHA1|MD5)$/ )
      or die 'Request for unknown digest algorithm to '. __PACKAGE__;

    exists $self->config->{hashedcookies}->{required}
      or $self->config->{hashedcookies}->{required} = 1;
    # not checked - perl's handling of truth will make junk values 'work'

    defined $self->config->{hashedcookies}->{key}
      or die '"key" is a required configuration parameter to '. __PACKAGE__;

    return $self->NEXT::setup(@_);
}


# remove and check hash in Cookie Values
sub prepare_cookies {
    my $c = shift;
    $c->NEXT::prepare_cookies(@_);
    $c->request->validhashedcookies(   {} );
    $c->request->invalidhashedcookies( {} );

    my $hasher = 'Digest::HMAC_'. $c->config->{hashedcookies}->{algorithm};
    my $hmac   = $hasher->new( $c->config->{hashedcookies}->{key} );

    while ( my ( $name, $cgicookie ) = each %{ $c->request->cookies } ) {
        my @values = @{ [ $cgicookie->value ] };
        my $digest = '';

        # restore cookie to original Value set by user
        if ( scalar @values % 2 == 0 ) {
            my $t = Tie::IxHash->new(@values);
            my $d = $t->Indices('_hashedcookies_digest');
            my $p = $t->Indices('_hashedcookies_padding');

            if ( defined $d ) {
                $digest = $t->Values($d);
                splice( @values, $d * 2, 2 );
            }

            if ( defined $p ) {
                splice( @values, $p * 2, 1 );
            }

            $cgicookie->value( \@values );
        }

        my $required = $c->config->{hashedcookies}->{required};
        if ( not $digest and not $required ) {
            $c->log->debug("HashedCookies skipping cookie:      $name")
              if $c->debug;
            $hmac->reset;
            next;
        }

        # now, we either have no digest but one is required,
        # or we have a digest that needs checking

        # $c->log->debug( "HashedCookies is hashing: ". $cgicookie->as_string );
        $hmac->add( $cgicookie->as_string );
        my $result = $hmac->hexdigest;    # WARNING!!! $hmac has now been RESET

         # $c->log->debug( "HashedCookies retrieved digest: '$digest'" )
         #   if $c->debug;
         # $c->log->debug( "HashedCookies generated digest: '$result'" )
         #   if $c->debug;

        if ( $digest eq $result ) {
            $c->log->debug("HashedCookies adding valid cookie:  $name")
              if $c->debug;
            ++$c->request->validhashedcookies->{$name};
        }
        else {
            $c->log->debug("HashedCookies found INVALID cookie: $name")
              if $c->debug;
            ++$c->request->invalidhashedcookies->{$name};
        }

        $hmac->reset;
    }

    return $c;
}


# check for illegal parameters in cookie set by App, and raise hell if found
sub finalize {
    # need to hook in here, early in the finalize sequence, because Catalyst has
    # been written to check $c->error *before* it goes on to call finalize_headers
    # and hence finalize_cookies.
    my $c = shift;

    while ( my ( $name, $cookie ) = each %{ $c->response->cookies } ) {

        # see finalize_cookies hook, below, for comments
        my $cgicookie = CGI::Cookie->new(
            -name  => $name,
            -value => $cookie->{value},
        );

        if (defined $cgicookie->value) {
            foreach ( @{ [ $cgicookie->value ] } ) {
                if (defined and m/^_hashedcookies_/) {
                    $c->log->debug('HashedCookies setting $c->error, illegal cookie param from App')
                        if $c->debug;
                    $c->error('Attempted use of restricted ("_hashedcookies_*") value in cookie');

                    # don't want to have dud cookie sent to client browser
                    delete $c->response->cookies->{$cgicookie->name};
                }
            }
        }
    }

    $c->NEXT::finalize(@_);
    return $c;
}


# alter all Cookie Values to include a hash
sub finalize_cookies {
    my $c = shift;

    if ($c->response->status =~ m/^5\d\d/) {
        $c->log->debug('HashedCookies finalize_cookies hook aborted due to 5xx error status')
            if $c->debug;
        $c->NEXT::finalize_cookies(@_);
        return $c;
    }

    my $hasher = 'Digest::HMAC_'. $c->config->{hashedcookies}->{algorithm};
    my $hmac   = $hasher->new( $c->config->{hashedcookies}->{key} );

    while ( my ( $name, $cookie ) = each %{ $c->response->cookies } ) {

        # creating a tmp CGI::Cookie is handy for as_string,
        # and also because we can consistenly use ->value as a list
        # 
        # only -name and -value are used because this is what CGI::Cookie->parse()
        # will pass back from an HTTP header - prepare_cookies needs identical hash
        my $cgicookie = CGI::Cookie->new(
            -name  => $name,
            -value => $cookie->{value},
        );

        # $c->log->debug( "HashedCookies is hashing: ". $cgicookie->as_string );
        $hmac->add( $cgicookie->as_string );

        # make sure that cookie ->value can be coerced into a hash upon retrieval
        if ( scalar @{ [ $cgicookie->value ] } % 2 == 1 ) {
            $cookie->{value} = [
                '_hashedcookies_padding' => @{ [ $cgicookie->value ] },
                '_hashedcookies_digest' => $hmac->hexdigest,
            ];
        }
        else {
            $cookie->{value} = [
                @{ [ $cgicookie->value ] },
                '_hashedcookies_digest' => $hmac->hexdigest,
            ];
        }

        $hmac->reset;
    }

    $c->NEXT::finalize_cookies(@_);
    return $c;
}


=head1 NAME

Catalyst::Plugin::HashedCookies - Tamper-resistant HTTP Cookies

=head1 VERSION

This document refers to version 0.02 of Catalyst::Plugin::HashedCookies,
released Monday August 22, 2005.

=head1 SYNOPSIS

 use Catalyst qw/HashedCookies/;
 MyApp->config->{hashedcookies} = {
     key       => $secret_key,
     algorithm => 'SHA1', # optional
     required  => 1,      # optional
 };
 MyApp->setup;

 # later, in another part of MyApp...

 print "this cookie tastes good!\n"
  if $c->request->valid_cookie('my_cookie_name');

=head1 DESCRIPTION

=head2 Overview

When HTTP cookies are used to store a user's state or identity it's important
that your application is able to distinguish legitimate cookies from those
that have been edited or created by a malicious user.

This module allows you to determine whether a cookie presented by a client was
created in its current state by your own application.

=head2 Implementation

HashedCookies adds a keyed cryptographic hash to each cookie that your
application creates, and checks every client-provided cookie for a valid hash.

This is done in a transparent way such that you do not need to change B<any>
application code that handles cookies when using this plugin. A cookie that
fails to contain a valid hash will still be available to your application
through C<< $c->request->cookie() >>.

Two additional methods within the Catalyst request object allow you to check
the status (in other words, the vailidity) of your cookies.

=head1 METHODS

=head2 Catalyst Request Object Methods

=over 4

=item C<< $c->request->valid_cookie($cookie_name) >>

If a cookie was successfully authenticated then this method will return True,
otherwise it will return False.

=item C<< $c->request->invalid_cookie($cookie_name) >>

If a cookie failed its authentication, then this method will return True,
otherwise it will return False. Please read the L</"CONFIGURATION"> section
below to understand what 'failed authentication' really means.

=back

=head1 CONFIGURATION

=over 4

=item key

 MyApp->config->{hashedcookies}->{key} = $secret_key;

This parameter is B<required>, and sets the secret key that is used to
generate a message authentication hash. Clearly, for a returned cookie to be
authenticated the same key must be used both when setting the cookie and
retrieving it.

=item algorithm

 MyApp->config->{hashedcookies}->{algorithm} = 'SHA1';
   # or
 MyApp->config->{hashedcookies}->{algorithm} = 'MD5';

This parameter is optional, and will default to C<SHA1> if not set. It
instructs the module to use the given message digest algorithm.

=item required

 MyApp->config->{hashedcookies}->{required} = 0;
   # or
 MyApp->config->{hashedcookies}->{required} = 1;

This parameter is optional, and will default to C<1> if not set.

If a cookie is read from the client but does not contain a HashedCookies hash
(i.e. this module was not running when the cookie was set), then this
parameter controls whether the cookie is ignored.

Setting this parameter to True means that a cookie without a hash is treated
as if it did have a hash, and therefore the authentication will fail. Setting
this parameter to False means that the cookie will be ignored.

When a cookie is ignored, neither C<< $c->request->valid_cookie() >> nor C<<
$c->request->invalid_cookie() >> will return True, but you can of course still
access the cookie through C<< $c->request->cookie() >>.

=back

=head1 DIAGNOSTICS

=over 4

=item 'Request for unknown digest algorithm to ...'

You have attempted to configure this module with an unrecognized message
digest algorithm. Please see the L</"CONFIGURATION"> section for the valid
algorithms.

=item '"key" is a required configuration parameter to ...'

You have forgotten to set the secret key that is used to generate a message
authentication hash. See the L</"SYNOPSIS"> or L</"CONFIGURATION"> section for
examples of how to set this parameter.

=item 'Attempted use of restricted ("_hashedcookies_*") value in cookie'

This module adds values to your cookie, and to avoid clashes with your own
values they are named in a special way. If you try to set a cookie with values
matching this special name format, your Catalyst Engine's default error
handler will be triggered, and the response status code will be set to "500".

You cannot trap such errors because they are raised after all the application
code has run, but you will see the above error in your log file, and your
Application will certainly halt so that Catalyst can display its error page.

=back

=head1 DEPENDENCIES

Other than the natural dependencies of L<Catalyst> and the contents of the
standard Perl distribution, you will need the following:

=over 4

=item *

Digest::HMAC

=back

=head1 BUGS

Please report any bugs or feature requests to
C<bug-catalyst-plugin-hashedcookies@rt.cpan.org>, or through the web interface
at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Catalyst-Plugin-HashedCookies>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 SEE ALSO

L<Catalyst>, L<Digest::HMAC_SHA1>, L<Digest::HMAC_MD5>

L<http://www.schneier.com/blog/archives/2005/08/new_cryptanalyt.html>

=head1 AUTHOR

Oliver Gorwits C<< <oliver.gorwits@oucs.ox.ac.uk> >>

=head1 ACKNOWLEDGEMENTS

All the helpful people in #catalyst.

=head1 COPYRIGHT & LICENSE

Copyright (c) The University of Oxford 2006. All Rights Reserved.

This program is free software; you can redistribute it and/or modify it under
the terms of version 2 of the GNU General Public License as published by the
Free Software Foundation.

This program is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to the Free Software Foundation, Inc., 51 Franklin
St, Fifth Floor, Boston, MA 02110-1301 USA

=cut

1;

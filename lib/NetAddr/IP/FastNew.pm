package NetAddr::IP::LazyInit;

use strict;
use warnings;
use NetAddr::IP qw(Zero Zeros Ones V4mask V4net netlimit);
use Socket qw(inet_pton AF_INET AF_INET6);
use NetAddr::IP::Util;
# the minimum version I test with.  5.10 doesn't support inet_pton.  This
# requirement will probably go away if I move the Fast new() functions to a
# new module.
use v5.12.5;

our $VERSION = eval '0.5';

=head1 NAME

NetAddr::IP::LazyInit - NetAddr::IP objects with deferred validation B<SEE DESCRIPTION BEFORE USING>

=head1 VERSION

0.5

=head1 SYNOPSIS

    use NetAddr::IP::LazyInit;

    my $ip = new NetAddr::IP::LazyInit( '10.10.10.5' );

=head1 DESCRIPTION

This module is designed to quickly create objects that may become NetAddr::IP
objects.  It accepts anything you pass to it without validation.  Once a
method is called that requires operating on the value, the full NetAddr::IP
object is constructed.

You can see from the benchmarks that once you need to instantiate NetAddr::IP
the speed becomes worse than if you had not used this module.  What I mean is
that this adds unneeded overhead if you intend to do IP operations on every
object you create.

=head1 WARNING


Because validation is deferred, this module assumes you will B<only ever give
it valid data>. If you try to give it anything else, it will happily accept it
and then die once it needs to inflate into a NetAddr::IP object.


=head1 CREDITS

This module was inspired by discussion with  Jan Henning Thorsen, E<lt>jhthorsen
at cpan.orgE<gt>, and example code he provided.  The namespace and part of the
documentation/source is inspired by DateTime::LazyInit by
Rick Measham, E<lt>rickm@cpan.orgE<gt>

I didn't have to do much so I hate to take author credit, but I am providing
the module, so complaints can go to me.

Robert Drake, E<lt>rdrake@cpan.orgE<gt>

=head1 TODO

If we could actually load NetAddr::IP objects in the background while nothing
is going on that would be neat.  Or we could create shortcut methods when the
user knows what type of input he has.  new_from_ipv4('ip','mask').  We might
be able to use Socket to build the raw materials and bless a new NetAddr::IP
object without going through it's validation.

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2014 by Robert Drake

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.7 or,
at your option, any later version of Perl 5 you may have available.

=cut

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(Compact Coalesce Zero Zeros Ones V4mask V4net netlimit);

# local copy for our functions because otherwise it takes 717ns/call to reference
my $ones = &Ones;
# this is to zero the ipv6 portion of the address.  This is used when we're
# building IPv4 objects.
my $zerov6 = pack('n6', (0,0,0,0,0,0));

my $masks = {
    1 => "\200\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0",
    10 => "\377\300\0\0\0\0\0\0\0\0\0\0\0\0\0\0",
    100 => "\377\377\377\377\377\377\377\377\377\377\377\377\360\0\0\0",
    101 => "\377\377\377\377\377\377\377\377\377\377\377\377\370\0\0\0",
    102 => "\377\377\377\377\377\377\377\377\377\377\377\377\374\0\0\0",
    103 => "\377\377\377\377\377\377\377\377\377\377\377\377\376\0\0\0",
    104 => "\377\377\377\377\377\377\377\377\377\377\377\377\377\0\0\0",
    105 => "\377\377\377\377\377\377\377\377\377\377\377\377\377\200\0\0",
    106 => "\377\377\377\377\377\377\377\377\377\377\377\377\377\300\0\0",
    107 => "\377\377\377\377\377\377\377\377\377\377\377\377\377\340\0\0",
    108 => "\377\377\377\377\377\377\377\377\377\377\377\377\377\360\0\0",
    109 => "\377\377\377\377\377\377\377\377\377\377\377\377\377\370\0\0",
    11 => "\377\340\0\0\0\0\0\0\0\0\0\0\0\0\0\0",
    110 => "\377\377\377\377\377\377\377\377\377\377\377\377\377\374\0\0",
    111 => "\377\377\377\377\377\377\377\377\377\377\377\377\377\376\0\0",
    112 => "\377\377\377\377\377\377\377\377\377\377\377\377\377\377\0\0",
    113 => "\377\377\377\377\377\377\377\377\377\377\377\377\377\377\200\0",
    114 => "\377\377\377\377\377\377\377\377\377\377\377\377\377\377\300\0",
    115 => "\377\377\377\377\377\377\377\377\377\377\377\377\377\377\340\0",
    116 => "\377\377\377\377\377\377\377\377\377\377\377\377\377\377\360\0",
    117 => "\377\377\377\377\377\377\377\377\377\377\377\377\377\377\370\0",
    118 => "\377\377\377\377\377\377\377\377\377\377\377\377\377\377\374\0",
    119 => "\377\377\377\377\377\377\377\377\377\377\377\377\377\377\376\0",
    12 => "\377\360\0\0\0\0\0\0\0\0\0\0\0\0\0\0",
    120 => "\377\377\377\377\377\377\377\377\377\377\377\377\377\377\377\0",
    121 => "\377\377\377\377\377\377\377\377\377\377\377\377\377\377\377\200",
    122 => "\377\377\377\377\377\377\377\377\377\377\377\377\377\377\377\300",
    123 => "\377\377\377\377\377\377\377\377\377\377\377\377\377\377\377\340",
    124 => "\377\377\377\377\377\377\377\377\377\377\377\377\377\377\377\360",
    125 => "\377\377\377\377\377\377\377\377\377\377\377\377\377\377\377\370",
    126 => "\377\377\377\377\377\377\377\377\377\377\377\377\377\377\377\374",
    127 => "\377\377\377\377\377\377\377\377\377\377\377\377\377\377\377\376",
    128 => "\377\377\377\377\377\377\377\377\377\377\377\377\377\377\377\377",
    13 => "\377\370\0\0\0\0\0\0\0\0\0\0\0\0\0\0",
    14 => "\377\374\0\0\0\0\0\0\0\0\0\0\0\0\0\0",
    15 => "\377\376\0\0\0\0\0\0\0\0\0\0\0\0\0\0",
    16 => "\377\377\0\0\0\0\0\0\0\0\0\0\0\0\0\0",
    17 => "\377\377\200\0\0\0\0\0\0\0\0\0\0\0\0\0",
    18 => "\377\377\300\0\0\0\0\0\0\0\0\0\0\0\0\0",
    19 => "\377\377\340\0\0\0\0\0\0\0\0\0\0\0\0\0",
    2 => "\300\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0",
    20 => "\377\377\360\0\0\0\0\0\0\0\0\0\0\0\0\0",
    21 => "\377\377\370\0\0\0\0\0\0\0\0\0\0\0\0\0",
    22 => "\377\377\374\0\0\0\0\0\0\0\0\0\0\0\0\0",
    23 => "\377\377\376\0\0\0\0\0\0\0\0\0\0\0\0\0",
    24 => "\377\377\377\0\0\0\0\0\0\0\0\0\0\0\0\0",
    25 => "\377\377\377\200\0\0\0\0\0\0\0\0\0\0\0\0",
    26 => "\377\377\377\300\0\0\0\0\0\0\0\0\0\0\0\0",
    27 => "\377\377\377\340\0\0\0\0\0\0\0\0\0\0\0\0",
    28 => "\377\377\377\360\0\0\0\0\0\0\0\0\0\0\0\0",
    29 => "\377\377\377\370\0\0\0\0\0\0\0\0\0\0\0\0",
    3 => "\340\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0",
    30 => "\377\377\377\374\0\0\0\0\0\0\0\0\0\0\0\0",
    31 => "\377\377\377\376\0\0\0\0\0\0\0\0\0\0\0\0",
    32 => "\377\377\377\377\0\0\0\0\0\0\0\0\0\0\0\0",
    33 => "\377\377\377\377\200\0\0\0\0\0\0\0\0\0\0\0",
    34 => "\377\377\377\377\300\0\0\0\0\0\0\0\0\0\0\0",
    35 => "\377\377\377\377\340\0\0\0\0\0\0\0\0\0\0\0",
    36 => "\377\377\377\377\360\0\0\0\0\0\0\0\0\0\0\0",
    37 => "\377\377\377\377\370\0\0\0\0\0\0\0\0\0\0\0",
    38 => "\377\377\377\377\374\0\0\0\0\0\0\0\0\0\0\0",
    39 => "\377\377\377\377\376\0\0\0\0\0\0\0\0\0\0\0",
    4 => "\360\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0",
    40 => "\377\377\377\377\377\0\0\0\0\0\0\0\0\0\0\0",
    41 => "\377\377\377\377\377\200\0\0\0\0\0\0\0\0\0\0",
    42 => "\377\377\377\377\377\300\0\0\0\0\0\0\0\0\0\0",
    43 => "\377\377\377\377\377\340\0\0\0\0\0\0\0\0\0\0",
    44 => "\377\377\377\377\377\360\0\0\0\0\0\0\0\0\0\0",
    45 => "\377\377\377\377\377\370\0\0\0\0\0\0\0\0\0\0",
    46 => "\377\377\377\377\377\374\0\0\0\0\0\0\0\0\0\0",
    47 => "\377\377\377\377\377\376\0\0\0\0\0\0\0\0\0\0",
    48 => "\377\377\377\377\377\377\0\0\0\0\0\0\0\0\0\0",
    49 => "\377\377\377\377\377\377\200\0\0\0\0\0\0\0\0\0",
    5 => "\370\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0",
    50 => "\377\377\377\377\377\377\300\0\0\0\0\0\0\0\0\0",
    51 => "\377\377\377\377\377\377\340\0\0\0\0\0\0\0\0\0",
    52 => "\377\377\377\377\377\377\360\0\0\0\0\0\0\0\0\0",
    53 => "\377\377\377\377\377\377\370\0\0\0\0\0\0\0\0\0",
    54 => "\377\377\377\377\377\377\374\0\0\0\0\0\0\0\0\0",
    55 => "\377\377\377\377\377\377\376\0\0\0\0\0\0\0\0\0",
    56 => "\377\377\377\377\377\377\377\0\0\0\0\0\0\0\0\0",
    57 => "\377\377\377\377\377\377\377\200\0\0\0\0\0\0\0\0",
    58 => "\377\377\377\377\377\377\377\300\0\0\0\0\0\0\0\0",
    59 => "\377\377\377\377\377\377\377\340\0\0\0\0\0\0\0\0",
    6 => "\374\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0",
    60 => "\377\377\377\377\377\377\377\360\0\0\0\0\0\0\0\0",
    61 => "\377\377\377\377\377\377\377\370\0\0\0\0\0\0\0\0",
    62 => "\377\377\377\377\377\377\377\374\0\0\0\0\0\0\0\0",
    63 => "\377\377\377\377\377\377\377\376\0\0\0\0\0\0\0\0",
    64 => "\377\377\377\377\377\377\377\377\0\0\0\0\0\0\0\0",
    65 => "\377\377\377\377\377\377\377\377\200\0\0\0\0\0\0\0",
    66 => "\377\377\377\377\377\377\377\377\300\0\0\0\0\0\0\0",
    67 => "\377\377\377\377\377\377\377\377\340\0\0\0\0\0\0\0",
    68 => "\377\377\377\377\377\377\377\377\360\0\0\0\0\0\0\0",
    69 => "\377\377\377\377\377\377\377\377\370\0\0\0\0\0\0\0",
    7 => "\376\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0",
    70 => "\377\377\377\377\377\377\377\377\374\0\0\0\0\0\0\0",
    71 => "\377\377\377\377\377\377\377\377\376\0\0\0\0\0\0\0",
    72 => "\377\377\377\377\377\377\377\377\377\0\0\0\0\0\0\0",
    73 => "\377\377\377\377\377\377\377\377\377\200\0\0\0\0\0\0",
    74 => "\377\377\377\377\377\377\377\377\377\300\0\0\0\0\0\0",
    75 => "\377\377\377\377\377\377\377\377\377\340\0\0\0\0\0\0",
    76 => "\377\377\377\377\377\377\377\377\377\360\0\0\0\0\0\0",
    77 => "\377\377\377\377\377\377\377\377\377\370\0\0\0\0\0\0",
    78 => "\377\377\377\377\377\377\377\377\377\374\0\0\0\0\0\0",
    79 => "\377\377\377\377\377\377\377\377\377\376\0\0\0\0\0\0",
    8 => "\377\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0",
    80 => "\377\377\377\377\377\377\377\377\377\377\0\0\0\0\0\0",
    81 => "\377\377\377\377\377\377\377\377\377\377\200\0\0\0\0\0",
    82 => "\377\377\377\377\377\377\377\377\377\377\300\0\0\0\0\0",
    83 => "\377\377\377\377\377\377\377\377\377\377\340\0\0\0\0\0",
    84 => "\377\377\377\377\377\377\377\377\377\377\360\0\0\0\0\0",
    85 => "\377\377\377\377\377\377\377\377\377\377\370\0\0\0\0\0",
    86 => "\377\377\377\377\377\377\377\377\377\377\374\0\0\0\0\0",
    87 => "\377\377\377\377\377\377\377\377\377\377\376\0\0\0\0\0",
    88 => "\377\377\377\377\377\377\377\377\377\377\377\0\0\0\0\0",
    89 => "\377\377\377\377\377\377\377\377\377\377\377\200\0\0\0\0",
    9 => "\377\200\0\0\0\0\0\0\0\0\0\0\0\0\0\0",
    90 => "\377\377\377\377\377\377\377\377\377\377\377\300\0\0\0\0",
    91 => "\377\377\377\377\377\377\377\377\377\377\377\340\0\0\0\0",
    92 => "\377\377\377\377\377\377\377\377\377\377\377\360\0\0\0\0",
    93 => "\377\377\377\377\377\377\377\377\377\377\377\370\0\0\0\0",
    94 => "\377\377\377\377\377\377\377\377\377\377\377\374\0\0\0\0",
    95 => "\377\377\377\377\377\377\377\377\377\377\377\376\0\0\0\0",
    96 => "\377\377\377\377\377\377\377\377\377\377\377\377\0\0\0\0",
    97 => "\377\377\377\377\377\377\377\377\377\377\377\377\200\0\0\0",
    98 => "\377\377\377\377\377\377\377\377\377\377\377\377\300\0\0\0",
    99 => "\377\377\377\377\377\377\377\377\377\377\377\377\340\0\0\0"
};


=head1 METHODS

=head2 new

This replaces the NetAddr::IP->new method with a stub that stores the
arguments supplied in a temporary variable and returns immediately.  No
validation is performed.

Once you call a method that can't be handled by LazyInit, a full NetAddr::IP
object is built and the request passed into that object.

   my $ip = NetAddr::IP::LazyInit->new("127.0.0.1");

=cut

sub new { my $class = shift; bless {x=>[@_]}, $class }


=head2 new_ipv4

Create a real NetAddr::IP from a single IPv4 address with almost no
validation.  This has more overhead than the LazyInit new() but it's much
faster if you make use of the IP object.

This only takes one argument, the single IP address.  Anything else will fail
in (probably) bad ways.  Validation is completely up to you and is not done
here.

   my $ip = NetAddr::IP::LazyInit->new_ipv4("127.0.0.1");

=cut


sub new_ipv4 {
    return bless {
        addr    => $zerov6 . inet_pton(AF_INET, $_[1]),
        mask    => $ones,
        isv6    => 0,
    }, 'NetAddr::IP';
}

=head2 new_ipv4_mask

Create a real NetAddr::IP from a IPv4 subnet with almost no
validation.  This has more overhead than the LazyInit new() but it's much
faster if you make use of the IP object.

This requires the IP address and the subnet mask as it's two arguments.
Anything else will fail in (probably) bad ways.  Validation is completely
up to the caller is not done here.

   my $ip = NetAddr::IP::LazyInit->new_ipv4_mask("127.0.0.0", "255.255.255.0");

=cut


sub new_ipv4_mask {
    return bless {
        addr    => $zerov6 . inet_pton(AF_INET, $_[1]),
        mask    => $zerov6 . inet_pton(AF_INET, $_[2]),
        isv6    => 0,
    }, 'NetAddr::IP';
}

=head2 new_ipv6

Create a real NetAddr::IP object from an IPv6 subnet with no validation.  This
is almost as fast as the lazy object.  The only caveat being it requires a
cidr mask.

   my $ip = NetAddr::IP::LazyInit->new_ipv6("fe80::/64");

=cut

sub new_ipv6 {
    my $pos = index($_[1],'/');
    my $ip = substr($_[1], 0, $pos-1);
    return bless { 'addr' => inet_pton(AF_INET6, $ip), 'mask' => $masks->{substr($_[1], $pos+1)}, 'isv6' => 1 }, 'NetAddr::IP';
}


=head2 addr

Returns the IP address of the object.  If we can extract the IP as a string
without converting to a real NetAddr::IP object, then we return that.
Currently it only returns IPv6 strings in lower case, which may break your
application if you aren't using the new standard.

    my $ip = NetAddr::IP::LazyInit->new("127.0.0.1");
    print $ip->addr;

=cut

sub addr {
    my $self = shift;
    if ($self->{x}->[0] =~ /^(.*?)(?:\/|$)/) {
        return lc($1);
    } else {
        return $self->inflate->addr;
    }
}

=head2 mask

Returns the subnet mask of the object.  If the user used the two argument
option then it returns the string they provided for the second argument.
Otherwise this will inflate to build a real NetAddr::IP object and return the
mask.

    my $ip = NetAddr::IP::LazyInit->new("127.0.0.1", "255.255.255.0");
    print $ip->mask;

=cut

sub mask {
    my $self = shift;
    if ($self->{x}->[1] && $self->{x}->[1] =~ /\D/) {
        return $self->{x}->[1];
    } else {
        return $self->inflate->mask;
    }
}

# everything below here aren't ment for speed or for users to reference.
# They're purely for compatibility with NetAddr::IP so that users can use this
# module like the real one.

sub can { NetAddr::IP->can($_[1]); }

sub Compact {
    for (@_) {
        $_->inflate if (ref($_) eq 'NetAddr::IP::LazyInit');
    }
    return NetAddr::IP::Compact(@_);
}



sub Coalesce {
    for (@_) {
        $_->inflate if (ref($_) eq 'NetAddr::IP::LazyInit');
    }
    return NetAddr::IP::Coalesce(@_);
}

sub import {
    if (grep { $_ eq ':rfc3021' } @_)
    {
        $NetAddr::IP::rfc3021 = 1;
        @_ = grep { $_ ne ':rfc3021' } @_;
    }
    if (grep { $_ eq ':old_storable' } @_) {
        @_ = grep { $_ ne ':old_storable' } @_;
    }
    if (grep { $_ eq ':old_nth' } @_)
    {
        $NetAddr::IP::Lite::Old_nth = 1;
        @_ = grep { $_ ne ':old_nth' } @_;
    }
    if (grep { $_ eq ':lower' } @_)
    {
        NetAddr::IP::Util::lower();
        @_ = grep { $_ ne ':lower' } @_;
    }
    if (grep { $_ eq ':upper' } @_)
    {
        NetAddr::IP::Util::upper();
        @_ = grep { $_ ne ':upper' } @_;
    }

  NetAddr::IP::LazyInit->export_to_level(1, @_);
}

# need to support everything that NetAddr::IP does
use overload (
    '@{}'   => sub { return [ $_[0]->inflate->hostenum ]; },
    '""'    => sub { return $_[0]->inflate->cidr() },
    '<=>'   => sub { inflate_args_and_run(\&NetAddr::IP::Lite::comp_addr_mask, @_); },
    'cmp'   => sub { inflate_args_and_run(\&NetAddr::IP::Lite::comp_addr_mask, @_); },
    '++'    => sub { inflate_args_and_run(\&NetAddr::IP::Lite::plusplus, @_); },
    '+'     => sub { inflate_args_and_run(\&NetAddr::IP::Lite::plus, @_); },
    '--'    => sub { inflate_args_and_run(\&NetAddr::IP::Lite::minusminus, @_); },
    '-'     => sub { inflate_args_and_run(\&NetAddr::IP::Lite::minus, @_); },
    '='     => sub { inflate_args_and_run(\&NetAddr::IP::Lite::copy, @_); },
    '=='    => sub {
        my $a = $_[0];
        $a->inflate if ref($_[0]) =~ /NetAddr::IP::LazyInit/;
        my $b = $_[1];
        $b->inflate if ref($_[1]) =~ /NetAddr::IP::LazyInit/;
        return ($a eq $b);
    },
    '!='    => sub {
        my $a = $_[0];
        $a->inflate if ref($_[0]) eq 'NetAddr::IP::LazyInit';
        my $b = $_[1];
        $b->inflate if ref($_[1]) eq 'NetAddr::IP::LazyInit';
        return ($a ne $b);
    },
    'ne'    => sub {
        my $a = $_[0];
        $a->inflate if ref($_[0]) eq 'NetAddr::IP::LazyInit';
        my $b = $_[1];
        $b->inflate if ref($_[1]) eq 'NetAddr::IP::LazyInit';
        return ($a ne $b);
    },
    'eq'    => sub {
        my $a = $_[0];
        $a->inflate if ref($_[0]) eq 'NetAddr::IP::LazyInit';
        my $b = $_[1];
        $b->inflate if ref($_[1]) eq 'NetAddr::IP::LazyInit';
        return ($a eq $b);
    },
    '>'     => sub { return &comp_addr_mask > 0 ? 1 : 0; },
    '<'     => sub { return &comp_addr_mask < 0 ? 1 : 0; },
    '>='    => sub { return &comp_addr_mask < 0 ? 0 : 1; },
    '<='    => sub { return &comp_addr_mask > 0 ? 0 : 1; },

);

sub comp_addr_mask {
    return inflate_args_and_run(\&NetAddr::IP::Lite::comp_addr_mask, @_);
}

sub inflate_args_and_run {
    my $func = shift;
    $_[0]->inflate if ref($_[0]) eq 'NetAddr::IP::LazyInit';
    $_[1]->inflate if ref($_[1]) eq 'NetAddr::IP::LazyInit';
    return &{$func}(@_);
}

sub AUTOLOAD {
  my $self = shift;
  my $obj = NetAddr::IP->new(@{ $self->{x} });
  %$self = %$obj;
  bless $self, 'NetAddr::IP';
  our $AUTOLOAD =~ /::(\w+)$/;
  return $self->$1(@_);
}

sub inflate {
    my $self = shift;
    my $method = shift;
    my $obj = NetAddr::IP->new(@{ $self->{x} });
    %$self = %$obj;
    bless $self, 'NetAddr::IP';
    return $method ? $self->method( @_ ) : $self;
}

1;

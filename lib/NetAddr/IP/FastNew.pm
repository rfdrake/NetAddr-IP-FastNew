package NetAddr::IP::FastNew;

use strict;
use warnings;
use NetAddr::IP qw(Zero Zeros Ones V4mask V4net netlimit);
# 1.95 required for inet_pton
use Socket 1.95 qw(inet_pton AF_INET AF_INET6);
use NetAddr::IP::Util;
# the minimum version I test with.  5.10 doesn't support inet_pton.
# MSWin32 also doesn't support Socket::inet_pton
use v5.12.5;

# The following code is from spamassassin.  I may use this to workaround Socket issues, but it only
# helps if Socket6 is available.  Currently this only affects two platforms on
# cpantesters.  OpenBSD (5.5) and GNUkfreebsd (8.1), so they could just upgrade to a
# version of Socket.pm that supports inet_pton (they're both running 1.94 so
# they only have to go up to 1.95)

# # try to load inet_pton from Socket or Socket6
# my $ip6 = eval {
#     require Socket;
#     Socket->VERSION(1.95);
#     Socket->import( 'inet_pton' );
#     1;
# } || eval {
#     require Socket6;
#     Socket6->import( 'inet_pton' );
#     1;
# };

our $VERSION = eval '0.3';

=head1 NAME

NetAddr::IP::FastNew - NetAddr::IP new() methods with no validation

=head1 VERSION

0.3

=head1 SYNOPSIS

    use NetAddr::IP::FastNew;

    my $ip = new NetAddr::IP::FastNew( '10.10.10.5' );

=head1 DESCRIPTION

This module is designed to quickly create NetAddr::IP objects.

If you have a situation where you need 200_000 NetAddr::IP objects then the
initialization speed can really become a problem.

=head1 CREDITS

Robert Drake, E<lt>rdrake@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2014 by Robert Drake

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.7 or,
at your option, any later version of Perl 5 you may have available.

=cut

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

Right now this just calls NetAddr::IP->new().

   my $ip = NetAddr::IP::FastNew->new("127.0.0.1");

=cut

sub new {
    # attempt to beat NetAddr::IP speeds by guessing the type of address and
    # initializing it.  This will probably not support nearly as many formats
    # as the original, but will be useful to some users who want something
    # fast and easy.
    my $class = shift;
    return NetAddr::IP->new(@_);
}


=head2 new_ipv4

Create a real NetAddr::IP from a single IPv4 address with almost no
validation.  This has more overhead than the FastNew new() but it's much
faster if you make use of the IP object.

This only takes one argument, the single IP address.  Anything else will fail
in (probably) bad ways.  Validation is completely up to you and is not done
here.

   my $ip = NetAddr::IP::FastNew->new_ipv4("127.0.0.1");

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
validation.

This requires the IP address and the subnet mask as it's two arguments.
Anything else will fail in (probably) bad ways.  Validation is completely
up to the caller is not done here.

   my $ip = NetAddr::IP::FastNew->new_ipv4_mask("127.0.0.0", "255.255.255.0");

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

   my $ip = NetAddr::IP::FastNew->new_ipv6("fe80::/64");

=cut

sub new_ipv6 {
    my $pos = index($_[1],'/');
    my $ip = substr($_[1], 0, $pos-1);
    return bless { 'addr' => inet_pton(AF_INET6, $ip), 'mask' => $masks->{substr($_[1], $pos+1)}, 'isv6' => 1 }, 'NetAddr::IP';
}


1;

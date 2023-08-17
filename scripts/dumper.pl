#! perl
use v5.14;
use strict;
use warnings;
use FindBin qw($Bin);
use File::Spec;
use lib File::Spec->catdir($Bin, '..', 'lib');
use Diogenes::Browser;

use IPC::Open3;
use Symbol 'gensym';

use utf8;
# binmode STDOUT, ':utf8';


my $query = Diogenes::Browser->new
  (
   -type => 'tlg',
  );

#say $query->parse_idt('0086');

my %works = $query->browse_works('0086');

say "$_ => $works{$_}" for sort keys %works;


for my $work (sort keys %works) {
  $query->seek_passage
    (
     '0086',
     "$work",
    );

  $query->browse_forward();
  # $query->browse_forward();
}

# while ( $query->browse_forward() ) {};

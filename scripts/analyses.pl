#!perl
use v5.14;
use strict;
use warnings;
use utf8;
use FindBin qw($Bin);
use File::Spec;

our %greek_analyses_indices;
our $greek_analyses_file =
  File::Spec->catfile($Bin, '..', 'data', 'greek-analyses.txt');
our $greek_analyses_index =
  File::Spec->catfile($Bin, '..', 'data', 'greek-analyses.idx');
my @alphabet = split //, 'abcdefghiklmnopqrstuwxyz';

sub load_greek_analyses_index {
  if (-e $greek_analyses_index) {
    read_greek_analyses_index();
  }
  else {
    make_greek_analyses_index();
    write_greek_analyses_index();
  }
}

sub make_greek_analyses_index {
  open my $analyses_fh, '<:raw', $greek_analyses_file
      or die "Unable to load analyses file: $!\n";


  my $letter = shift @alphabet;
  while (<$analyses_fh>) {
    if (m/^$letter/) {
      $greek_analyses_indices{$letter} =
	tell($analyses_fh) - length($_);
      $letter = shift @alphabet
	or last;
    }
  }
}

sub write_greek_analyses_index {
  open FH, '>', $greek_analyses_index
    or die "Unable to open analyses index: $!\n";
  say FH "$_ $greek_analyses_indices{$_}"
    for sort keys %greek_analyses_indices;
  close FH;
}

sub read_greek_analyses_index {
  open FH, '<', $greek_analyses_index
    or die "Unable to load analyses index: $!\n";
  while (<FH>) {
    if (m/([a-ik-uw-z]) (\d+)/) {
      $greek_analyses_indices{$1} = $2;
    }
  }
  for (@alphabet) {
    die "Error in $greek_analyses_index"
      unless exists $greek_analyses_indices{$_};
  }
}

load_greek_analyses_index();

say "$_: $greek_analyses_indices{$_}"
  for sort keys %greek_analyses_indices;


# open my $analyses_fh, '<:raw',
#   File::Spec->catfile($Bin, '..', 'data', 'greek-analyses.txt')
#   or die "Unable to load analyses file: $!\n";

# my $lines;
# # Seek the miscellanea at the beginning
# seek $analyses_fh, 0, 0;

# while (<$analyses_fh> and tell($analyses_fh) < 4378305) {
#   $lines++;
# }

# say my $letter = 'c';
# my $next_letter = $letter;
# $next_letter++;

# seek $analyses_fh, ( $greek_analyses_indices{$letter} - 1 ), 0;
# # my $lines = 0;

# while (<$analyses_fh>) {
#   if (tell($analyses_fh) < $greek_analyses_indices{$next_letter}) {
#   }
#   else {
#     say;
#     last;
#   }
# }

# # while (<$analyses_fh>) {
# #   if (m/^[a-z]/g) {
# #     say;
# #     say tell;
# #     last;
# #   }
# # }

# $greek_analyses_indices{a}   =   4378305;
# $greek_analyses_indices{b}   =  24253005;
# $greek_analyses_indices{c}   =  25763280;
# $greek_analyses_indices{d}   =  26578660;
# $greek_analyses_indices{e}   =  34167053;
# $greek_analyses_indices{f}   =  56042524;
# $greek_analyses_indices{g}   =  58151215;
# $greek_analyses_indices{h}   =  59344372;
# $greek_analyses_indices{i}   =  60982309;
# $greek_analyses_indices{k}   =  62194387;
# $greek_analyses_indices{l}   =  72808318;
# $greek_analyses_indices{m}   =  74541048;
# $greek_analyses_indices{n}   =  78518971;
# $greek_analyses_indices{o}   =  79738819;
# $greek_analyses_indices{p}   =  82479687;
# $greek_analyses_indices{q}   =  98962768;
# $greek_analyses_indices{r}   = 100491933;
# $greek_analyses_indices{s}   = 101189374;
# $greek_analyses_indices{t}   = 110684367;
# $greek_analyses_indices{u}   = 113694911;
# $greek_analyses_indices{w}   = 117566966;
# $greek_analyses_indices{x}   = 118204885;
# $greek_analyses_indices{y}   = 119684869;
# $greek_analyses_indices{z}   = 120080005;
# $greek_analyses_indices{EOF} = 120437326;


# # greek-analyses.txt
# #      offset     line
# # *:        0        0
# # a:   4378305   52730
# # b:  24253005  191828
# # c:  25763280  204871
# # d:  26578660  211428
# # e:  34167053  266569
# # f:  56042524  427268
# # g:  58151215  444235
# # h:  59344372  454568
# # i:  60982309  467266
# # k:  62194387  476589
# # l:  72808318  554417
# # m:  74541048  569193
# # n:  78518971  601085
# # o:  79738819  611017
# # p:  82479687  633819
# # q:  98962768  752092
# # r: 100491933  764597
# # s: 101189374  769897
# # t: 110684367  837052
# # u: 113694911  861690
# # w: 117566966  888601
# # x: 118204885  893768
# # y: 119684869  905479
# # z: 120080005  908883
# #    120437326  911872


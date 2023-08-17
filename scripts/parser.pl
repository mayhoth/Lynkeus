#! perl
use v5.14;
use strict;
use warnings;
use FindBin qw($Bin);
use File::Spec;
use lib File::Spec->catdir($Bin, '..', 'lib');
use Diogenes::Search;

use IPC::Open3;
use Symbol 'gensym';

use utf8;
binmode STDOUT, ':utf8';

# use Benchmark qw(:all) ;

# Morpheus setup
my $morphlib = File::Spec->catfile
  ($Bin, '..', '..', 'lynkeus_utils', 'morpheus-perseids', 'stemlib');
my $morpheus_bin= File::Spec->catfile
  ($Bin, '..', '..', 'lynkeus_utils', 'morpheus-perseids', 'bin', 'cruncher');
$ENV{MORPHLIB} = $morphlib;

# get forms
my @forms;
say "Enter some forms to be analyzed:";
while (<STDIN>) {
  chomp;
  push @forms, $_;
}

my %analysis = morpheus(@forms);

say "$_: $analysis{$_}" for sort keys %analysis;

# Send forms to morpheus, retrieve the output as a string
sub morpheus {
  my @forms = @_;

  # translate forms into something morpheus understands
  for (@forms) {
    s#·#:#g;
    # s#\(#( #g;
    # s#\)# )#g;
  }

  my $morpheus_output;
  # my @morpheus_output;
  my %analysis;

  # fork into morpheus cruncher
  my $pid = open3 my $morpheus_in, my $morpheus_out, my $morpheus_err=gensym,
    $morpheus_bin;
  defined $pid
    or die "open3() failed: $!";

  # give cruncher our forms, one at a time
  say { $morpheus_in } $_ for @forms;
  close $morpheus_in;

  # retrieve cruncher's output
  {
    local $/ = undef;
    $morpheus_output = <$morpheus_out>;
  }
  close $morpheus_out;

  # wait for cruncher to exit, get its retval
  waitpid ( $pid, 0 );
  my $morpheus_exit_status = $? >> 8;

  # process the data
  my $word = '';
  my @not_found;
  open my $str_fh, '<:utf8', \$morpheus_output
    or die "Could not open string filehandle: $!";

  while (<$str_fh>) {
    chomp;
    if (/^\S+$/) {
      if ($word) {
	warn "No analysis found for $word!";
	push @not_found, $word;
      }
      $word = $_;
    }
    elsif (/^\<NL\>/) {
      # formatting
      s#\t+# | #g;
      s#</NL>$##;
      s#</NL>#\n\t#g;

      # beta to unicode
      while (s/\<NL\>(\w) (\S+)/\t$1 ###/) {
	my $basic_form = beta_to_utf8($2);
	s/###/$basic_form/s;
      }
      $analysis{$word} = $_;
      $word = '';
    }
    else { die "Flow error!" }
  }


  return %analysis;
}

# Taken over from Perseus.pm, lines 62–80
sub beta_to_utf8 {
  my $text = shift;
  my %fake_obj;    # Dreadful hack
  $fake_obj{encoding} = 'UTF-8';

  $text =~ tr/a-z/A-Z/;
  # $text =~ s/_//g; # delete combining macron
  # $text =~ s/\^//g; # delete combining breve
  $text =~ s!_([/\=()]+)!$1_!g;
  $text =~ s!\^([/\=()]+)!$1_!g;
  Diogenes::Base::beta_encoding_to_external(\%fake_obj, \$text);
  # $text =~ s/([\x80-\xff])_/$1\314\204/g; # combining macron
  $text =~ s/_/\314\204/g;
  # $text =~ s/([\x80-\xff])\^/$1\314\206/g; # combining breve
  $text =~ s/\^/\314\204/g;
  # Decode from a 'binary string' to a UTF-8 'text string'
  return Encode::decode('utf-8', $text);
};

sub utf8_to_beta {
  lc Diogenes::UnicodeInput->unicode_greek_to_beta(shift);
}

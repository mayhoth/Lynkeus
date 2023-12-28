#! perl
use v5.14;
use strict;
use warnings;
use utf8;
use FindBin qw($Bin);
use File::Spec;
use Data::Dumper;
use Deep::Hash::Utils qw(reach slurp);
use Diogenes::Search;
# binmode STDOUT, ':utf8';

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
  $greek_analyses_indices{aa} = -s $greek_analyses_file;

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
    for sort
    { $greek_analyses_indices{$a} <=> $greek_analyses_indices{$b} }
    keys %greek_analyses_indices;
  close FH;
}

sub read_greek_analyses_index {
  open FH, '<', $greek_analyses_index
    or die "Unable to load analyses index: $!\n";
  while (<FH>) {
    if (m/([a-ik-uw-z]+) (\d+)/) {
      $greek_analyses_indices{$1} = $2;
    }
  }
  for (@alphabet) {
    die "Error in $greek_analyses_index"
      unless exists $greek_analyses_indices{$_};
  }
}

sub get_lemma {
  my $input_word = shift;

  my $strict = 0;
  if ($input_word =~ m![\/=()]!) {
    $strict = 1;
  }

  # open greek-analyses.txt, get the matches
  open my $analyses_fh, '<:raw',
    File::Spec->catfile($Bin, '..', 'data', 'greek-analyses.txt')
    or die "Unable to load analyses file: $!\n";

  my @analyses_lines = ();
  my $letter = substr $input_word, 0, 1;
  ++(my $next_letter = $letter);

  # Seek the miscellanea at the beginning
  seek $analyses_fh, 0, 0;
  my $switch = 0;
  while (<$analyses_fh>) {
    if (tell($analyses_fh) > $greek_analyses_indices{a} and not $switch) {
      seek $analyses_fh, $greek_analyses_indices{$letter}, 0;
      $switch++;
    }
    last if tell($analyses_fh) > $greek_analyses_indices{$next_letter};

    my $line = $_;
    /^(\S+)/;
    my $headword = $1;
    if ($headword) {
      $headword =~ tr#/\\=()|\*##d unless $strict;
      push @analyses_lines, $line if $headword eq $input_word;
    }
  }
  close $analyses_fh;

  say for @analyses_lines;
  say "";

  # retrieve single matches
  my %analyses;
  for (@analyses_lines) {
    m/^(\S+)/;
    my $headword = $1;

    while (m/{(.*?)}/g) {
      my $analysis = $1;
      my ($number, $lemma, $translation, $morphology, $dialects);

      if ($analysis =~ s/^(\S+)\s+\S+\s+//) { $number = $1 }
      if ($analysis =~ s/^(\S+)\t//)        { $lemma = $1 }
      if ($analysis =~ s/([^\t]+?)\t//)     { $translation = $1 }

      my %hash;
      $hash{number} = $number;
      $hash{lemma} = $lemma;
      $hash{translation} = $translation;
      $hash{analysis} = $analysis;
      $hash{headword} = $headword;

      my $key = $hash{lemma} . " (" . $hash{translation} . ")";
      $analyses{$headword}{$key} = \%hash;
    }
  }

  return %analyses;
}

sub get_forms {
  my $number = shift;

  open my $lemmata_fh, '<:raw',
    File::Spec->catfile($Bin, '..', 'data', 'greek-lemmata.txt')
    or die "Unable to load lemmata file: $!\n";

  my @forms = ();
  while (<$lemmata_fh>) {
    /^\S+\s+(\S+)/;
    my $lemma_number = $1;
    if ($lemma_number == $number) {
      my $line = $_;
      $line =~ s/^\S+\s+\S+//;

      while ($line =~ s/^\t(\S+)\s+([^\t]*)//g) {
	my $form = $1;
	my $analysis = $2;
	push @forms, $form;
      }
    }
  }
  close $lemmata_fh;

  return @forms;
}

sub make_lemma_patterns {
  my $ref = shift;
  my @forms = @$ref;
  tr#/\\=()|\*##d for @forms;

  @forms = sort { length($b) <=> length($a) } @forms;
  say "@forms\n";
  my $stem_min = 1;
  $stem_min = length[$#forms] <= $stem_min
    ? $stem_min
    : length[$#forms];

  my $depth = length( $forms[0] ) - 1;
  my %patterns;
  my %paths;

  # make up the hash
  for my $level (0..$depth) {
    for my $form (@forms) {
      if ( length($form) > $level ) {
	my $letter = substr($form, $level, 1);

	my $command = '$patterns';
	for (0..$level) {
	  my $key = substr($form, $_, 1);
	  $command .= '{' . $key . '}';
	}
	if ( length($form) - 1 > $level ) {
	  $command .= ' = {}';
	}
	else {
	  $command .= '{0} = $form;';
	}
	eval $command;
      }
    }
  }

  # tidy up:
  sub tidy_up {
    my $hashref = shift;
    my $retval = 0;

    for my $key (keys %{ $hashref }) {
      next if $key eq '0';
      # my %subhash = %{ $hashref->{$key} };
      my @subkeys = keys %{ $hashref->{$key} };

      if (@subkeys == 1) {
	if ($subkeys[0] eq '0') {} # hitting the end of the road
	else {
	  $retval++;
	  my $subkey = $subkeys[0];
	  say my $combined = $key . $subkey;
	  $hashref->{$combined} = $hashref->{$key}{$subkey};
	  delete $hashref->{$key};
	  $retval += tidy_up(\%{ $hashref->{$combined} });
	}
      }
      else {
	$retval = tidy_up(\%{ $hashref->{$key} });
      }
    }
    say $retval;
    return $retval;
  }
while ( tidy_up(\%patterns) ) {};


  
  # sub tidy_up {
  #   my $hashref = shift;
  #   my $retval = 0;
  #   for my $first (keys %{ $hashref }){
  #     next if $first eq '0';

  #     if (scalar keys %{ $hashref->{$first} } == 1 ) {
  # 	for my $second (keys %{ $hashref->{$first} }) {
  # 	  next if $second eq '0';
  # 	  my $combined = $first . $second;
  # 	  $hashref->{$combined} = $hashref->{$first}{$second};
  # 	  delete $hashref->{$first};
  # 	  $retval++;
  # 	}
  #     }
  #   }
  #   return $retval;
  # }

  # # first on the surface...
  # while ( tidy_up(\%patterns) ){};

  # # ...then go deep!
  # my $processed;
  # do {
  #   $processed = 0;
  #   my @batch = slurp(\%patterns);

  #   while (@batch) {
  #     my $ref = shift @batch;
  #     last unless defined $ref;
  #     my @list = @$ref;
  #     my $path = '$patterns';
  #     @list = @list[ 0..($#list - 3) ];
  #     my %paths;

  #     for my $index (0..$#list){
  # 	$path .= '{' . $list[$index] . '}';
  # 	my $command = '$processed = tidy_up(\%{ ' . $path . ' });';
  # 	eval $command;
  # 	last if $processed;
  #     }
  #     last if $processed;
  #   }
  # } while $processed;

  # say "";
  print Dumper (%patterns);
  # while (my @list = reach(\%patterns)) {
  #   say "@list";
  # }
  # say "";

  # unroll the hash, make the patterns
  # sub hash_to_pattern {
  #   my $hashref = shift;
  #   my %hash = %{ $hashref };
  #   my @keys = keys %hash;
  #   my $optional = 0;
  #   my @subpatterns;

  #   return '' if (@keys == 1 and $keys[0] eq '0');

  #   for my $key (@keys){
  #     if ($key eq '0') { $optional = 1 }
  #     else {
  # 	my $subpattern = hash_to_pattern(\%{ $hash{$key}  });
  # 	push @subpatterns, "$key$subpattern";
  #     }
  #   }
  #   my $pattern = join '|', @subpatterns;
  #   $pattern = "($pattern)";
  #   $pattern = "$pattern?" if $optional;
  #   return $pattern;
  # }

  # my @pattern_list;
  # for my $key (keys %patterns) {
  #   my $pattern = $key;
  #   my %subhash = %{ $patterns{$key} };
  #   $pattern .= hash_to_pattern(\%subhash);
  #   push @pattern_list, $pattern;
  # }
  # return @pattern_list;
  return 0;
}

# Alteration der Endungen

# Syllabisches Augment

# Temporales Augment

# Apokope

# Spiritus

# Akzente: atomic grouping (Achtung bei Wechsel des Akzents in die
# Endung)
# sort { length($a) <=> length($b) }

# (?>a\)/ei|a\)ei/)d(e|w)
# a\)id(e|w)

### MAIN
load_greek_analyses_index();

print "Enter word: ";
chomp ( my $word = <STDIN>);
my %analyses = get_lemma($word);

my @headwords = sort keys %analyses
  or die "No lemma found!\n";

for (0..$#headwords){ say "$_: $headwords[$_]" }

print "Select headword: ";
chomp ( my $num = <STDIN> );
$num = $num || 0;
my $headword = $headwords[$num] or die "No headword #$num!\n";
my @lemmata = sort keys %{ $analyses{$headword} };

for (0..$#lemmata){ say "$_: $lemmata[$_]" }

print "Select lemma: ";
chomp ( my $lem_num = <STDIN> );
$lem_num = $lem_num || 0;
my $lemma = $lemmata[$lem_num] or die "No lemma #$lem_num!\n";
my $number = $analyses{$headword}{$lemma}{number};

my @forms = get_forms($number);

my @patterns = make_lemma_patterns(\@forms);

# say "";

say for @patterns;

my $query = Diogenes::Search->new

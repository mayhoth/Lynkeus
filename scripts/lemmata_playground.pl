#! perl
use v5.14;
use strict;
use warnings;
use utf8;
use FindBin qw($Bin);
use File::Spec;
use Data::Dumper;
use Storable qw(dclone);
use Deep::Hash::Utils qw(reach slurp);
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

  # my %patterns;

  # # Endungs-Algorhythmus:
  # @forms = sort { length($a) <=> length($b) } @forms;
  # say "@forms\n";

  # my @not_processed;
  # do {
  #   @forms = @not_processed if @not_processed;
  #   @not_processed = ();
  #   my $word = shift @forms;
  #   my $length = length($word) - 1;
  #   my $matcher = substr($word, 0, $length);
  #   my $last_letter = substr($word, -1);
  #   $patterns{$matcher}{$last_letter} = $word;

  #   say "@forms";

  #   for my $next (@forms) {
  #     if ($next =~ /^$matcher/) {
  # 	# say my $end_pos = $+[0];
  # 	#say my $new_length = length($next) - $end_pos;
  # 	my $ending = substr($next, $length);
  # 	$patterns{$matcher}{$ending} = $next;
  #     }
  #     else { push @not_processed, $next }
  #   }
  #   say "@not_processed";
  #   # return;
  # } while @not_processed;

  # # Stamm-Algorhythmus, Tiefe vor Breite
  # @forms = sort { length($b) <=> length($a) } @forms;
  # say "@forms\n";

  # my $min_length = 2;
  # my @not_processed;
  # do {
  #   #setup
  #   @forms = @not_processed if @not_processed;
  #   @not_processed = ();
  #   say my $word = shift @forms;
  #   my $length = $min_length;
  #   my $matcher = substr($word, 0, $length);
  #   my $rest = substr($word, $length);
  #   $patterns{$matcher}{$rest} = $word;

  #   # get the first level keys
  #   for my $next_form (@forms) {
  #     if ($next_form =~ /^$matcher/) {
  # 	my $ending = substr($next_form, $length);
  # 	$patterns{$matcher}{$ending} = $next_form;
  #     }
  #     else { push @not_processed, $next_form }
  #   }

  #   # go in deep...
  #   my %unmatched = ();
  #   my $path = \%patterns;
  #   my $level = 1;

  #   while (length($rest) > 1) {
  #     $level++;
  #     $path = $path->{$matcher};
  #     $matcher = substr($rest, 0, 1);
  #     $rest    = substr($rest, 1);
  #     $path->{$matcher} = {};

  #     my @endings = sort keys %{ $path };
  #     for my $next_ending (@endings) {
  # 	if ($next_ending =~ /^$matcher/) {
  # 	  my $new_ending = substr($next_ending, 1);
  # 	  $path->{$matcher}{$new_ending} = $path->{$next_ending};
  # 	  delete $path->{$next_ending};
  # 	}
  # 	else {
  # 	  $unmatched{$level} = 
  # 	    push @unmatched, $next_ending;
  # 	}
  #     }
  #   }

  #   # fill the gaps
  #   @unmatched = sort { length($b) <=> length($a) } @unmatched;
  #   for my $next_unmatched (@unmatched) {

  #   }

  #   say $level;
  #   say "@unmatched";
  #   #} while @unmatched;

  # } while @not_processed;

  # Stamm-Algorhythmus, Breite vor Tiefe
  # Reste des Ref-ansatzes
  # my %paths;
  # $paths{$form} = \%{ $patterns{$letter} };
  # say my $href = $paths{$forms[0]};
  # ${ $href }{neu} = {};
  # ${ $paths{$form} }{$letter} = {};
  # $paths{$form} = \%{ ${ $paths{$form} }{$letter}};
  #  print Dumper (%paths);
  #  say for sort keys %patterns;

  @forms = sort { length($b) <=> length($a) } @forms;
  say "@forms\n";
  my $stem_min = 1;

  say my $depth = length( $forms[0] ) - 1;
  my %patterns;
  my %paths;

  # make up the hash
  for my $level (0..$depth) {
    for my $form (@forms) {
      if ( length($form) > $level ) {
	my $letter = substr($form, $level, 1);
	my $path = '$patterns';
	for (0..$level) {
	  my $key = substr($form, $_, 1);
	  $path .= '{' . $key . '}';
	}
	if ( length($form) - 1 > $level ) {
	  my $command = $path . ' = {}';
	  eval $command;
	}
	else {
	  my $command = $path . '{0} = $form;';
	  eval $command;
	}
      }
    }
  }

  # tidy up
  sub tidy_up {
    my $hashref = shift;
    my $retval = 0;
    # if (ref $hashref) {
    for my $first (keys %{ $hashref }){
      next if $first eq '0';
      # scalar keys %{ $hashref };
      # scalar keys %{ $hashref->{$first} };

      # if (ref $hashref->{$first}) {
      if (scalar keys %{ $hashref->{$first} } == 1 ) {
	for my $second (keys %{ $hashref->{$first} }) {
	  next if $second eq '0';
	  # if (scalar keys %{ $hashref } == 1) {
	    say "$first $second";
	  my $combined = $first . $second;
	  $hashref->{$combined} = $hashref->{$first}{$second};
	  delete $hashref->{$first};
	  # $hashref->first = 1;
	    $retval++;
	  # }
	}
      }
    }
    return $retval;
  }

  # first on the surface...
  while ( tidy_up(\%patterns) ) {};

  # ...then go deep!
  my $processed;
  do {
    $processed = 0;
    my @batch = slurp(\%patterns);
    while (@batch) {
      my $ref = shift @batch;
      last unless defined $ref;
      my @list = @$ref;
      my $path = '$patterns';
      say @list = @list[ 0..($#list - 3) ];
      my %paths;
      for my $index (0..$#list){
	$path .= '{' . $list[$index] . '}';
	# $paths{$index} = $path;
	my $command = '$processed = tidy_up(\%{ ' . $path . ' });';
	eval $command;
	last if $processed;
      }
      last if $processed;
      # for my $index (reverse 0..$#list){
      # 	my $retval = 0;
      # 	my $command = '$retval = tidy_up(\%{ ' . $paths{$index} . ' });';
      # 	eval $command;
      # 	$processed += $retval;
      # 	# die $@ if $@;
      # }
    }
    # $processed = 0;
  } while $processed;

  say "";
  print Dumper (%patterns);
  while (my @list = reach(\%patterns)) {
    say "@list";
  }
  say "";
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

# say for @patterns;

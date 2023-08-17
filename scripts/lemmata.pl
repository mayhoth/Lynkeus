#! perl
use v5.14;
use strict;
use warnings;
use utf8;
use FindBin qw($Bin);
use File::Spec;
use lib File::Spec->catdir($Bin, '..', 'lib');
use Data::Dumper;
use Diogenes::Search;
use Benchmark qw(:all) ;
# binmode STDOUT, ':utf8';

our $chop_optional_groups = 0;

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
  $greek_analyses_indices{EOF} = -s $greek_analyses_file;

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
    if (m/([a-ik-uw-z]|EOF) (\d+)/) {
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
  say my $letter = substr $input_word, 0, 1;
  say my $next_letter = do {
    my $index;
    for (0..$#alphabet){
      $index = $_ and last if $alphabet[$_] eq $letter;
    }
    say $index;
    $alphabet[++$index] || 'EOF';    
  };

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
  my $max_alt = shift || 10000;
  my $stem_min = shift || 1;
  my @forms = @$ref;
  tr#/\\=()|\*##d for @forms; 	# no accents
  tr#'#I# for @forms;		# make ' safe; will be undone in the end!

  @forms = sort { length($b) <=> length($a) } @forms;
  $stem_min = (length[$#forms] < $stem_min)
    ? length[$#forms]
    : $stem_min;
  say $stem_min;

  my $depth = length( $forms[0] ) - 1;
  my %patterns;
  my %paths;

  # make up the hash
  # stem
  for my $form (@forms) {
    my $stem = substr($form, 0, $stem_min);
    if ( length($form)  > $stem_min ) {
      $patterns{$stem} = {}
    }
    else {
      $patterns{$stem}{0} = $form
    }
  }

  # rest
  for my $level ($stem_min..$depth) {
    for my $form (@forms) {
      if ( length($form) > $level ) {
	my $letter = substr($form, $level, 1);

	my $command = '$patterns';
	my $stem = substr($form, 0, $stem_min);
	$command .= '{' . $stem . '}';
	for ($stem_min..$level) {
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

  # version without stem_min
  # for my $level (0..$depth) {
  #   for my $form (@forms) {
  #     if ( length($form) > $level ) {
  # 	my $letter = substr($form, $level, 1);

  # 	my $command = '$patterns';
  # 	for (0..$level) {
  # 	  my $key = substr($form, $_, 1);
  # 	  $command .= '{' . $key . '}';
  # 	}
  # 	if ( length($form) - 1 > $level ) {
  # 	  $command .= ' = {}';
  # 	}
  # 	else {
  # 	  $command .= '{0} = $form;';
  # 	}
  # 	eval $command;
  #     }
  #   }
  # }

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
	  my $combined = $key . $subkey;
	  $hashref->{$combined} = $hashref->{$key}{$subkey};
	  delete $hashref->{$key};
	  $retval += tidy_up(\%{ $hashref->{$combined} });
	}
      }
      else {
	$retval = tidy_up(\%{ $hashref->{$key} });
      }
    }
    return $retval;
  }
  while ( tidy_up(\%patterns) ) {};

  # say "";
  # print Dumper (%patterns);
  # while (my @list = reach(\%patterns)) {
  #   say "@list";
  # }
  # say "";

  # unroll the hash, make the patterns
  sub hash_to_pattern {
    my $hashref = shift;
    my %hash = %{ $hashref };
    my @keys = keys %hash;
    my $optional = 0;
    my @subpatterns;

    return '' if (@keys == 1 and $keys[0] eq '0');

    for my $key (@keys){
      if ($key eq '0') { $optional = 1 }
      else {
	my $subpattern = hash_to_pattern(\%{ $hash{$key}  });
	push @subpatterns, "$key$subpattern";
      }
    }
    my $pattern = join '|', @subpatterns;
    $pattern = "($pattern)";
    if ($optional) {
      $pattern = ($chop_optional_groups)
	? ''
	: "$pattern?";
    }
    # $pattern = "$pattern?" if $optional;
    return $pattern;
  }

  # undo over-optimization
  # helper function
  sub split_regex {
    my $subre = shift;
    my $parens_count = 0;
    my $strlength = length($subre);
    my @pos;
    for (my $i = 0; $i < $strlength; $i++) {
      if ( substr($subre, $i, 1) eq '(' ) { $parens_count++ }
      if ( substr($subre, $i, 1) eq ')' ) { $parens_count-- }
      if ( substr($subre, $i, 1) eq '|'
	   and $parens_count == 0 ) {
	push @pos, $i;
      }
    }
    push @pos, $strlength;

    my @split;
    for my $i (0..$#pos) {
      my $pos = $pos[$i];
      my $lastpos = ($i == 0) ? 0 : $pos[$i-1] + 1;
      my $length = $pos - $lastpos;
      my $split = ($pos == $strlength)
	? substr ($subre, $lastpos)
	: substr ($subre, $lastpos, $length);
      push @split, $split;
    }
    return @split;
  }

  sub decompose_regex {
    my $pattern = shift;
    my $max_alt = shift; 
    my $alterations = $pattern =~ tr/\|//;
    my @patterns;

    if ($alterations > $max_alt) {
      if ( $pattern =~ m#^([^()]+)\((.*)\)$# ) {
	my $stem = $1;
	my @rest = split_regex($2);
	@patterns = map { "$stem$_" } @rest;
      }
      elsif ( $pattern =~ m#^([^()]+)\((.*)\)\?$# ) { # group is optional
	my $stem = $1;
	my @rest = split_regex($2);
	@patterns = map { "$stem$_" } @rest;
	push @patterns, $stem;
      }
      else {die "Malformed pattern #pattern!"}

      @patterns = map { decompose_regex($_, $max_alt) } @patterns;
    }
    else { push @patterns, $pattern }
    return @patterns;
  }

  my @pattern_list;
  for my $key (keys %patterns) {
    my $pattern = $key;
    my %subhash = %{ $patterns{$key} };
    $pattern .= hash_to_pattern(\%subhash);
    my @patterns = decompose_regex($pattern, $max_alt);
    push @pattern_list, @patterns;
  }

  @pattern_list = map { tr/I/'/; $_ } @pattern_list; # reinsert '
  return @pattern_list;
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
my $max_alt = $ARGV[0] || 100;
my $stem_min = $ARGV[1] || 1;

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
say "FORMS:";
say for sort @forms;

my @patterns = make_lemma_patterns(\@forms, $max_alt, $stem_min);

@patterns = ($chop_optional_groups)
  ? map { " $_ "} @patterns
  : map { " $_ "} @patterns;

@patterns = sort { length($a) <=> length($b) } @patterns;
say "";
# say for @patterns;
for (0..$#patterns) {
  my $number = $_ + 1;
  my $count = $patterns[$_] =~ tr/\|//;
  $count = sprintf "%3d", $count;
  say "#$number $count x |: $patterns[$_]\n"
}

# my $query = Diogenes::Search->new
#   (
#    -type => 'tlg',
#    -pattern_list => \@patterns,
#   );

# $query->select_authors(-author_nums => [86]);
# my $str;
# { local *STDOUT;
#   open STDOUT, '>', \$str;
#   $query->do_search;
# }

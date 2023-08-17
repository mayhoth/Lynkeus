#! perl
use v5.36;
use lib '../lib';
use Diogenes::Indexed;

my $query = Diogenes::Indexed->new
  (
   -type => 'tlg',
   -pattern => ' kuwn '
  );
$query->select_authors
  (-author_regex => 'Aristot');
$query->pgrep;

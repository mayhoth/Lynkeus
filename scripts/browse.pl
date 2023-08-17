#! perl
use v5.36;
use lib '../lib';
use Diogenes::Browser;

my $query = Diogenes::Browser->new
  (
   -type => 'tlg',
  );

my @result = $query->seek_passage
  (
   $query->parse_idt('0086'),
   '1',
   # (1, 1, 0)
  );
map say, @result;

while ( $query->browse_forward() ) {};

# print "\n";





#! perl
use v5.36;
use lib '../lib';
use Diogenes::Browser;

my $offset = 5160469;

my $q = Diogenes::Browser::Lynkeus->new
  (
   -type => 'tlg',
  );

my $auth = sprintf "%04d", 86;
my $work = 34;
my $start = $q->get_relative_offset($offset, 86, 34);


my @offset = $q->seek_passage
  (
   $auth,
   '34',
#   (1, '1448a', 10)
  );

# $start = $q->get_relative_offset($offset[0], 86, 34);

@offset = $q->browse_forward($start, -1);say for @offset;
while ((my $inp = <STDIN>) ne "q\n")
  {
    @offset = $q->browse_forward(@offset);say ""; say for @offset;
    say $q->{current_work};
    say $q->{work_num};
  }
@offset = $q->browse_forward(@offset);say for @offset;
@offset = $q->browse_backward(@offset);say for @offset;
@offset = $q->browse_backward(@offset);say for @offset;




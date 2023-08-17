use v5.14;
use strict;
use warnings;
use Module::Build;
Module::Build->VERSION('0.4004');

my $builder = Module::Build->new(
    module_name         => 'Lynkeus',
    license             => 'gpl_3',
    dist_author         => q{Michael Neidhart <Neidhart@lmu.de>},
    dist_version_from   => 'lib/Lynkeus.pm',
    release_status      => 'stable',
    configure_requires => {
        'Module::Build' => '0.4004',
    },
    test_requires => {
        'Test::More' => '0',
    },
    requires => {
        #'ABC'              => '1.6',
        #'Foo::Bar::Module' => '5.0401',
    },
    add_to_cleanup     => [ 'Lynkeus-*' ],
);

$builder->create_build_script();

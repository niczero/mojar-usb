use 5.010_001;
use strict;
use warnings;

use ExtUtils::MakeMaker;

WriteMakefile(
  NAME         => 'Mojar::Usb',
  VERSION_FROM => 'lib/Mojar/Usb.pm',
  ABSTRACT     => 'Interfaces to USB devices',
  AUTHOR       => 'Nic Sandfield <niczero@cpan.org>',
  LICENSE      => 'artistic_2',
  META_MERGE   => {
    requires  => {perl => 5.010001},
    resources => {
      homepage    => 'http://niczero.github.com/mojar-usb',
      license     => 'http://www.opensource.org/licenses/artistic-license-2.0',
      repository  => 'http://github.com/niczero/mojar-usb',
      bugtracker  => 'http://github.com/niczero/mojar-usb/issues'
    },
    no_index => {directory => ['test']}
  },
  BUILD_REQUIRES => {'Test::More' => 0},
  CONFIGURE_REQUIRES => {'ExtUtils::MakeMaker' => '6.30'},
  PREREQ_PM => {Mojolicious => 3.33, 'Device::USB' => 0.35},
  EXE_FILES => [],
  test => {TESTS => 'test/*.t'}
);

use Mojo::Base -strict;
use Test::More;

use_ok 'Mojar::Usb';
diag "Testing Mojar::Usb $Mojar::Usb::VERSION, Perl $], $^X";
use_ok 'Mojar::Usb::Temper';

done_testing();

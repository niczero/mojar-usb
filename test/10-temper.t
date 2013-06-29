use Mojo::Base -strict;
use Test::More;

use Device::USB;
use Mojar::Usb::Temper;

subtest q{Basic} => sub {
  is +(Mojar::Usb::Temper->timeout), 90, 'timeout';
  is +(Mojar::Usb::Temper->vendor), 0x1130, 'vendor';
  is +(Mojar::Usb::Temper->product), 0x660c, 'product';
#  ok ! defined Mojar::Usb::Temper::_write(undef, undef, 0x60), 'lower limit';
#  ok ! defined Mojar::Usb::Temper::_write(undef, undef, 0x69), 'upper limit';
};

SKIP: {
  skip 'set TEST_TEMPER to enable this test (developer only!)', 1
    unless $ENV{TEST_TEMPER};

my $usb;

subtest q{Device::USB} => sub {
  ok my $du = Device::USB->new, 'new';
  ok my @list = $du->list_devices(
    Mojar::Usb::Temper->vendor,
    Mojar::Usb::Temper->product), 'list_devices';
  is ref($list[0]), 'Device::USB::Device', 'found something';
  $usb = $list[0];
};

subtest q{Constructor} => sub {
  ok my $mut = Mojar::Usb::Temper->new(usb => $usb), 'new';
  cmp_ok $mut->id, '==', 0x58, 'id';
  diag $mut->celsius, ' is the temperature';
  diag $mut->fahrenheit, ' in Fahrenheit';
};

};

done_testing();

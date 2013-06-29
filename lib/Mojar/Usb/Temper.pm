package Mojar::Usb::Temper;
use Mojo::Base -base;

our $VERSION = 0.121;

use Device::USB;
use Time::HiRes 'sleep';

# Attributes

has vendor => 0x1130;   # Tenx Technology, Inc
has product => 0x660c;  # HidTEMPer USB thermometer
# Microdia device is 0xc45:0x7401

has range_max => 120;
has range_min => -40;
has timeout => 90;  # ms
has pause => 400;  # ms
has samples => 3;
has average => 1;  # 0: median; 1: mean

has previous => sub { [0, 0] };
has sensors => 0x54;

# Public methods

sub scan {
  my ($proto, %param) = @_;
  my $vendor = $param{vendor} || $proto->vendor;
  my $product = $param{product} || $proto->product;
  return map +($proto->new(usb => $_)),
      Device::USB->new->list_devices($vendor, $product);
}

sub new {
  my ($proto, %param) = @_;
  my $usb = delete $param{usb} // die 'Missing required USB device';

  $usb = \$usb unless ref $usb;
  $usb->get_driver_np($_) and $usb->detach_kernel_driver_np($_)
    for 0, 1;
  $usb->open or die 'Failed to open device';
  $usb->set_configuration(1) if $^O eq 'MSWin32';
  $usb->claim_interface($_) and die 'Failed to claim interface'
    for 0, 1;

  my $device = $proto->SUPER::new(%param, usb => $usb);
  my $id = $device->id;
  if ($id == 0x59) {
		# TEMPer2
		$device->{sensors} = [0x54, 0x53];
	}
  elsif ($id == 0x5b) {
		# TEMPerNTC
		$device->{sensors} = [0x54, 0x41];
	}
	_write($usb, $device->timeout, 0x43)
		if $id == 0x58 or $id == 0x59 or $id == 0x5b;
	return $device;
}

sub id {
  my ($self) = @_;
	return $self->{id} if $self->{id};
  return undef unless $self->{usb};
  return $self->{id} =
      (_read($self->{usb}, $self->timeout, $self->pause, 0x52))[1];
}

sub calibration {
  my ($self) = @_;
  return undef unless $self->{usb};
  return [ (_read($self->{usb}, $self->timeout, $self->pause, 0x52))[2,3] ];
  # [2] : Calibration val one for internal sensor
  # [3] : Calibration val two for internal sensor
  # [4] : Calibration val one for external sensor
  # [5] : Calibration val two for external sensor
}

sub temperature {
  my ($self, $command) = @_;
  my $iterations = $self->samples || 1;
  my $usb = $self->{usb} // die 'Missing required device';
	my @readings;
  for my $i (0 .. $iterations - 1) {
    my @buffer = _read($usb, $self->timeout, $self->pause, $command);
    $readings[$i] = $buffer[0] < 128
        ? $buffer[0] + $buffer[1] / 256
        : $buffer[0] - 255 - $buffer[1] / 256;
		sleep(.1);
  }
  $self->{previous}[1] = $self->previous->[0];
	if ($self->average) {
		# Mean
		my $total = 0;
		$total += $_ for @readings;
		return $self->{previous}[0] = sprintf '%.*f', ($iterations + 1) / 2,
				$total / $iterations;
	}
	else {
		# Median
		my @sorted = sort {$a <=> $b} @readings;
		return $self->{previous}[0] = $sorted[sprintf '%.0f', $iterations / 2];
	}
}

sub celsius {
  my ($self) = @_;
  my $sensors = $self->sensors;
  return $self->temperature($sensors) unless ref $sensors;
  return [ map +($self->temperature($_)), @$sensors ];
}

sub fahrenheit {
  my $celsius = $_[0]->celsius;
  my $conversion = sub { $_[0] * 9 / 5 + 32 };
  return $conversion->($celsius) unless ref $celsius;
  return [ map +($conversion->($_)), @$celsius ];
}

sub DESTROY {
  my ($self) = @_;
  $self->{usb}->release_interface(0) if $self->{usb};
  $self->{usb}->release_interface(1) if $self->{usb};
  delete $self->{usb} if $self->{usb};
}

# Private methods

sub _read {
  my ($usb, $timeout, $pause, @cmds) = @_;
  my $buffer = 0;
  
  # Open device
  my $check = _command($usb, $timeout, 32, 0xA, 0xB, 0xC, 0xD, 0x0, 0x0, 0x2);
  # Request data
  $check   += _command($usb, $timeout, 32, @cmds);
  # Padding to clear i2c bus
  $check   += _command($usb, $timeout, 32, 0x0) for 0 .. 6;
  # Close device
  $check   += _command($usb, $timeout, 32, 0xA, 0xB, 0xC, 0xD, 0x0, 0x0, 0x1);

  die "Device returned wrong qty of bytes (expected 320, got $check)"
    unless $check == 320;

  sleep $pause / 1000;
  $check = $usb->control_msg(
      0xA1,     # Req type
      0x1,      # Req
      0x300,    # Value
      0x1,      # Index
      $buffer,  # Recepticle
      32,       # Qty bytes
      $timeout
  );

  die "Device returned wrong qty of bytes (expected 32, got $check)"
    unless $check == 32;

  return wantarray ? unpack 'C*', $buffer : $buffer;
}

sub _write {
  my ($usb, $timeout, @cmds) = @_;
  
  my $check = _command($usb, $timeout, 32, 0xA, 0xB, 0xC, 0xD, 0x0, 0x0, 0x2);
  $check   += _command($usb, $timeout, 32, @cmds);
  $check   += _command($usb, $timeout, 32, 0x0) for 0 .. 6;

  die "Device returned wrong qty of bytes (expected 288, got $check)"
    unless $check == 288;

  return $check;
}

sub _command {
  my ($usb, $timeout, $qty, @cmds) = @_;

  my $buffer = join '', map(chr, @cmds), map chr, (0 x ($qty - @cmds));

  my $check = $usb->control_msg(
      0x21,     # Req type
      0x9,      # Req
      0x200,    # Value
      0x1,      # Index
      $buffer,  # Recepticle
      $qty,     # Qty bytes
      $timeout
  );

  die "Device returned wrong qty of bytes (expected $qty, got $check)"
    unless $check == $qty;

  return $check;
}

1;
__END__

=head1 NAME

Mojar::Usb::Temper - Interface to HidTEMPer USB thermometer

=head1 SYNOPSIS

  my @devices = Mojar::Usb::Temper->scan;
  say 'fahrenheit: ', $_->fahrenheit for @devices;

  # or with more control...
  my @devices = Mojar::Usb::Temper->scan(
    vendor => 0x1130, product => 0x660c
  );
  $_->samples(5)    # 5 measurements per temperature request
      ->average(0)  # and use the median value
    for @devices;
  for (1 .. 10) {
    for my $dev (@devices) {
      my $c = ref($dev->celsius) ? $dev->celsius->[0] : $dev->celsius;
      say 'id: ', $dev->id;
      say 'calibration: ', $dev->calibration->[0];
      say 'celsius: ', $c, '; compared to :', $dev->previous->[1];
    }
    sleep 2;
  }

=head1 DESCRIPTION

Provides an interface for taking temperature measurements from the TEMPer range
of low-cost USB thermometers.  It supports the TEMPer1, both sensors of the
TEMPer2, and the internal sensor of the TEMPerNTC.

=head1 ATTRIBUTES

L<Mojar::Usb::Temper> implements the following attributes.

=head2 vendor

  $device->vendor(0xc45);
  $vendor = $device->vendor;

The vendor part of the USB device signature.  This partly determines which USB
devices are recognised.

=head2 product

  $device->product(0x7401);
  $product = $device->product;

The product part of the USB device signature.  This partly determines which USB
devices are recognised.

=head2 range_max

  $device->range_max(100);
  $max = $device->range_max;  # defaults to 120

The highest expected value.  Purely informational.

=head2 range_min

  $device->range_min(0);
  $min = $device->range_min;  # defaults to -40

The lowest expected value.  Purely informational.

=head2 timeout

  $device->timeout(120);
  $timeout = $device->timeout;  # defaults to 90ms

The USB timeout in milliseconds before a request for data is aborted.

=head2 pause

  $device->pause(500);
  $pause = $device->pause;  # defaults to 400ms

The sleep time in milliseconds between requesting info from the device and
reading it.  A value of around 400ms is believed safe; smaller values give
increasing possibility of false readings.

=head2 samples

  $device->samples(1);
  $samples = $device->samples;  # defaults to 3

The number of temperature samples to take before concluding a temperature; can
be any positive number.

=head2 average

  $device->average(0);  # Use median
  $device->average(1);  # Use mean
  $averaging_type = $device->average;

The type of average to use.  (Has no effect if $device->samples == 1.)  The
median is used if 0; the mean is used if 1.  (There may be additional types in
the future, eg discard outlying values then take the mean.)

=head2 sensors

  $device->sensors(0x54);  # Single sensor
  $device->sensors([0x54, 0x53]);  # Double sensors

Set the command codes required for each sensor.  Only required if the code
doesn't already cater for your model.

=head1 METHODS

=head2 scan

  @devices = Mojar::Usb::Temper->scan;

Scan the USB bus for matching devices.  Can be passed C<vendor> and C<product>
identifiers as a hash.

=head2 new

  $device = Mojar::Usb::Temper->new(usb => $usb, timeout => 140, ...);

Create a new Mojar::Usb::Temper device from a raw USB device, with other
attributes being optional.  You probably don't want to call this directly unless
you already have to talk to C<Device::USB>.

=head2 id

  $id = $device->id;

Get the model identifier for this device.  eg 0x59 for the HidTEMPer2.

=head2 calibration

  $internal_calibration = join ':', $device->calibration->[0,1];

Calibration values for each sensor.  Values for the external sensor are in
C<[2,3]>.  I wish I could play with setting these values, but so far they appear
to be read-only.

=head2 celsius

  $deg_c = $device->celsius->[0];

Get the sampled temperature in degrees Celsius for all sensors on this device.
Returns a scalar if the device has only one sensor.

=head2 fahrenheit

  $deg_f = $device->fahrenheit->[0];

Get the sampled temperature in degrees Fahrenheit for all sensors on this
device.  Returns a scalar if the device has only one sensor.

=head2 temperature

  $deg_c = $device->temperature(0x54);

Get the sampled temperature in degrees Celsius for the specified sensor.  You
should use one of the methods above instead, unless you want to avoid spending
time sampling a sensor you're ignoring.

=head1 RATIONALE

There are various tools for getting readings from your thermometer(s), including
a very popular perl module.  The other tools may support more devices and return
temperature readings quicker, but at the cost of coarser resolution, less
control, less reliable values, and sometimes segmentation faults.  One
deployment of this code is to control a high-cost central heating boiler for my
young family through the dark winters on a wind-swept island off the North-West
coast of Europe.

=cut

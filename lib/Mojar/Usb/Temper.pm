package Mojar::Usb::Temper;
use Mojo::Base -base;

our $VERSION = 0.001;

use Device::USB;
use Mojar::Util 'dumper';
use Time::HiRes 'sleep';

# Attributes

has vendor => 0x1130;   # Tenx Technology, Inc
has product => 0x660c;  # HidTEMPer USB thermometer
# Microdia device is 0xc45:0x7401

has range_max => 120;
has range_min => -40;
has timeout => 90;  # ms
has samples => 3;
has average => 1;  # 0: median; 1: mean

has 'previous';
has sensors => 0x54;

# Public methods

sub scan {
  my ($proto, %param) = @_;
  return map +($proto->new(usb => $_)),
      Device::USB->new->list_devices($proto->vendor, $proto->product);
}

sub new {
  my ($proto, %param) = @_;
  my $usb = $param{usb} // die 'Missing required USB device';

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
  return $self->{id} = (_read($self->{usb}, $self->timeout, 0x52))[1];
}

sub calibration {
  my ($self) = @_;
  return undef unless $self->{usb};
  return [ (_read($self->{usb}, $self->timeout, 0x52))[2,3] ];
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
    my @buffer = _read($usb, $self->timeout, $command);
    $readings[$i] = $buffer[0] < 128
        ? $buffer[0] + $buffer[1] / 256
        : $buffer[0] - 255 - $buffer[1] / 256;
		sleep(.1);
  }
	if ($self->average) {
		# Mean
		my $total = 0;
		$total += $_ for @readings;
		return sprintf '%.*f', ($iterations + 1) / 2,
				$total / $iterations;
	}
	else {
		# Median
		my @sorted = sort {$a <=> $b} @readings;
		return $sorted[sprintf '%.0f', $iterations / 2];
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
  my ($usb, $timeout, @cmds) = @_;
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

  sleep 0.4;
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

  my @devices = Mojar::Usb::Temper->scan;

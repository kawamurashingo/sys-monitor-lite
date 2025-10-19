package Sys::Monitor::Lite;
use strict;
use warnings;
use POSIX qw(uname);
use Time::HiRes qw(sleep);
use JSON::PP;

our $VERSION = '0.01';

sub collect_all {
    my %data;
    $data{timestamp} = _timestamp();
    $data{system} = _system_info();
    $data{cpu} = _cpu_usage();
    return \%data;
}

sub _system_info {
    my @u = uname();
    return { os => $u[0], kernel => $u[2], hostname => $u[1] };
}

sub _cpu_usage {
    open my $fh, '<', '/proc/stat' or return {};
    my ($user, $nice, $system, $idle, $iowait) = (split /\s+/, (grep { /^cpu\s/ } <$fh>)[0])[1..5];
    close $fh;
    sleep 0.1;
    open $fh, '<', '/proc/stat' or return {};
    my ($u2, $n2, $s2, $i2, $w2) = (split /\s+/, (grep { /^cpu\s/ } <$fh>)[0])[1..5];
    close $fh;
    my $diff_total = ($u2+$n2+$s2+$i2+$w2) - ($user+$nice+$system+$idle+$iowait);
    my $diff_used  = ($u2+$n2+$s2) - ($user+$nice+$system);
    my $pct = $diff_total ? 100 * (1 - ($diff_used / $diff_total)) : 0;
    return { usage_pct => { total => sprintf("%.1f", 100 - $pct) } };
}

sub to_json {
    return JSON::PP->new->canonical->encode(shift);
}

sub _timestamp {
    my @t = gmtime();
    return sprintf("%04d-%02d-%02dT%02d:%02d:%02dZ", $t[5]+1900,$t[4]+1,@t[3,2,1,0]);
}

1;
__END__

=head1 NAME

Sys::Monitor::Lite - Lightweight system monitoring toolkit with JSON output

=head1 SYNOPSIS

  use Sys::Monitor::Lite qw(collect_all to_json);
  print Sys::Monitor::Lite::to_json(Sys::Monitor::Lite::collect_all());

=head1 DESCRIPTION

A minimal system monitor that outputs structured JSON data
for easy automation and integration with jq-lite.


package Sys::Monitor::Lite;
use strict;
use warnings;
use POSIX qw(uname);
use Time::HiRes qw(sleep);
use JSON::PP ();
use Scalar::Util qw(looks_like_number);

our $VERSION = '0.01';

my %COLLECTORS = (
    system => \&_system_info,
    cpu    => \&_cpu_usage,
    load   => \&_load_average,
    mem    => \&_memory_usage,
    disk   => \&_disk_usage,
    net    => \&_network_io,
);

sub collect_all {
    return collect();
}

sub collect {
    my ($which) = @_;
    my @names;
    if (!defined $which) {
        @names = qw(system cpu load mem disk net);
    } elsif (ref $which eq 'ARRAY') {
        @names = @$which;
    } else {
        @names = @_;
    }

    my %data = (timestamp => _timestamp());
    for my $name (@names) {
        my $collector = $COLLECTORS{$name} or next;
        my $value = eval { $collector->() };
        next if $@;
        $data{$name} = $value;
    }
    return \%data;
}

sub _system_info {
    my @u = uname();
    my $uptime = _uptime_seconds();
    return {
        os           => $u[0],
        kernel       => $u[2],
        hostname     => $u[1],
        architecture => $u[4],
        uptime_sec   => $uptime,
    };
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
    my $diff_idle  = ($i2+$w2) - ($idle+$iowait);
    my $used_pct = _percent($diff_total - $diff_idle, $diff_total);
    return {
        cores     => _cpu_cores(),
        usage_pct => { total => $used_pct },
    };
}

sub _load_average {
    open my $fh, '<', '/proc/loadavg' or return {};
    my $line = <$fh> // '';
    close $fh;
    my ($l1, $l5, $l15) = (split /\s+/, $line)[0..2];
    return {
        '1min'  => _maybe_number($l1),
        '5min'  => _maybe_number($l5),
        '15min' => _maybe_number($l15),
    };
}

sub _memory_usage {
    open my $fh, '<', '/proc/meminfo' or return {};
    my %info;
    while (my $line = <$fh>) {
        next unless $line =~ /^(\w+):\s+(\d+)/;
        $info{$1} = $2 * 1024;
    }
    close $fh;

    my $total      = $info{MemTotal} // 0;
    my $available  = $info{MemAvailable} // ($info{MemFree} // 0);
    my $free       = $info{MemFree} // 0;
    my $buffers    = $info{Buffers} // 0;
    my $cached     = ($info{Cached} // 0) + ($info{SReclaimable} // 0);
    my $used       = $total - $available;
    my $swap_total = $info{SwapTotal} // 0;
    my $swap_free  = $info{SwapFree} // 0;
    my $swap_used  = $swap_total - $swap_free;

    return {
        total_bytes      => $total,
        available_bytes  => $available,
        used_bytes       => $used,
        free_bytes       => $free,
        buffers_bytes    => $buffers,
        cached_bytes     => $cached,
        used_pct         => _percent($used, $total),
        swap             => {
            total_bytes => $swap_total,
            used_bytes  => $swap_used,
            free_bytes  => $swap_free,
            used_pct    => _percent($swap_used, $swap_total),
        },
    };
}

sub _disk_usage {
    open my $fh, '<', '/proc/mounts' or return [];
    my %seen;
    my @disks;
    while (my $line = <$fh>) {
        my ($device, $mount, $type) = (split /\s+/, $line)[0..2];
        next if $seen{$mount}++;
        next if $mount =~ m{^/(?:proc|sys|dev|run|snap)};
        next if $type =~ /^(?:proc|sysfs|tmpfs|devtmpfs|cgroup.+|rpc_pipefs|overlay)$/;

        my @stat = eval { POSIX::statvfs($mount) };
        next unless @stat;
        my ($bsize, $frsize, $blocks, $bfree, $bavail) = @stat;
        my $total = $blocks * $frsize;
        my $free  = $bavail * $frsize;
        my $used  = $total - ($bfree * $frsize);

        push @disks, {
            mount        => $mount,
            filesystem   => $device,
            type         => $type,
            total_bytes  => $total,
            used_bytes   => $used,
            free_bytes   => $free,
            used_pct     => _percent($used, $total),
        };
    }
    close $fh;
    return \@disks;
}

sub _network_io {
    open my $fh, '<', '/proc/net/dev' or return [];
    my @ifaces;
    while (my $line = <$fh>) {
        next if $line =~ /^(?:Inter| face)/;
        $line =~ s/^\s+//;
        my ($iface, @fields) = split /[:\s]+/, $line;
        next unless defined $iface;
        my ($rx_bytes, $rx_packets, undef, undef, undef, undef, undef, undef,
            $tx_bytes, $tx_packets) = @fields;
        push @ifaces, {
            iface      => $iface,
            rx_bytes   => _maybe_number($rx_bytes),
            rx_packets => _maybe_number($rx_packets),
            tx_bytes   => _maybe_number($tx_bytes),
            tx_packets => _maybe_number($tx_packets),
        };
    }
    close $fh;
    return \@ifaces;
}

sub to_json {
    my ($data, %opts) = @_;
    my $encoder = JSON::PP->new->canonical->ascii(0);
    if ($opts{pretty}) {
        $encoder = $encoder->pretty;
    }
    return $encoder->encode($data);
}

sub _timestamp {
    my @t = gmtime();
    return sprintf("%04d-%02d-%02dT%02d:%02d:%02dZ", $t[5]+1900,$t[4]+1,@t[3,2,1,0]);
}

sub available_metrics {
    return sort keys %COLLECTORS;
}

sub _percent {
    my ($num, $den) = @_;
    return 0 unless defined $num && defined $den && $den;
    return sprintf('%.1f', ($num / $den) * 100);
}

sub _uptime_seconds {
    open my $fh, '<', '/proc/uptime' or return undef;
    my $line = <$fh> // '';
    close $fh;
    my ($uptime) = split /\s+/, $line;
    return _maybe_number($uptime);
}

sub _cpu_cores {
    my $count = 0;
    if (open my $fh, '<', '/proc/cpuinfo') {
        while (my $line = <$fh>) {
            $count++ if $line =~ /^processor\s*:\s*\d+/;
        }
        close $fh;
    }
    return $count || undef;
}

sub _maybe_number {
    my ($value) = @_;
    return undef unless defined $value;
    return looks_like_number($value) ? 0 + $value : $value;
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


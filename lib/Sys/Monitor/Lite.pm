package Sys::Monitor::Lite;
use strict;
use warnings;
use POSIX qw(uname);
use Time::HiRes qw(sleep);
use JSON::PP ();
use Scalar::Util qw(looks_like_number);

our $VERSION = '0.02';

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
    my $data = _memory_usage_proc();
    $data ||= _memory_usage_sysctl();
    $data ||= _memory_usage_fallback();
    return $data;
}

sub _memory_usage_proc {
    open my $fh, '<', '/proc/meminfo' or return undef;
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

sub _memory_usage_sysctl {
    # macOS support is explicitly out of scope for this distribution, so skip
    # any sysctl-based memory collection on Darwin. This avoids trying to
    # parse the platform-specific output formats that caused the upstream
    # test failures when run on macOS. Other platforms fall back to the
    # existing sysctl-based logic when available.
    return undef if $^O eq 'darwin';

    my $total = _run_sysctl('hw.memsize');
    return undef unless defined $total && looks_like_number($total);

    my $pagesize = _run_sysctl('hw.pagesize');
    $pagesize = 4096 unless defined $pagesize && looks_like_number($pagesize) && $pagesize > 0;

    my %vm_stats = _vm_stat_pages();
    my $free_pages   = ($vm_stats{'Pages free'} // 0) + ($vm_stats{'Pages speculative'} // 0);
    my $inactive     = $vm_stats{'Pages inactive'} // 0;
    my $cached_bytes = $inactive * $pagesize;
    my $free_bytes   = $free_pages * $pagesize;
    my $available    = $free_bytes + $cached_bytes;
    $available = $total if $available <= 0 || $available > $total;
    my $used         = $total - $available;
    $used = 0 if $used < 0;

    my ($swap_total, $swap_used, $swap_free) = _sysctl_swap_usage();

    return {
        total_bytes      => $total + 0,
        available_bytes  => $available + 0,
        used_bytes       => $used + 0,
        free_bytes       => $free_bytes + 0,
        buffers_bytes    => 0,
        cached_bytes     => $cached_bytes + 0,
        used_pct         => _percent($used, $total),
        swap             => {
            total_bytes => $swap_total,
            used_bytes  => $swap_used,
            free_bytes  => $swap_free,
            used_pct    => _percent($swap_used, $swap_total),
        },
    };
}

sub _memory_usage_fallback {
    return {
        total_bytes      => 0,
        available_bytes  => 0,
        used_bytes       => 0,
        free_bytes       => 0,
        buffers_bytes    => 0,
        cached_bytes     => 0,
        used_pct         => 0,
        swap             => {
            total_bytes => 0,
            used_bytes  => 0,
            free_bytes  => 0,
            used_pct    => 0,
        },
    };
}

sub _disk_usage {
    my %seen;
    my @disks;
    my $has_statvfs = POSIX->can('statvfs');
    my $df_stats    = _df_stats();

    if (open my $fh, '<', '/proc/mounts') {
        while (my $line = <$fh>) {
            my ($device, $mount, $type) = (split /\s+/, $line)[0..2];
            next if $seen{$mount}++;
            next if $mount =~ m{^/(?:proc|sys|dev|run|snap)};
            next if $type =~ /^(?:proc|sysfs|tmpfs|devtmpfs|cgroup.+|rpc_pipefs|overlay)$/;
            next unless defined $mount && length $mount;
            next unless -d $mount;

            my ($total, $used, $free);
            if ($has_statvfs) {
                my @stat = eval { POSIX::statvfs($mount) };
                next unless @stat;
                my ($bsize, $frsize, $blocks, $bfree, $bavail) = @stat;
                $total = $blocks * $frsize;
                $free  = $bavail * $frsize;
                $used  = $total - ($bfree * $frsize);
            } else {
                my $info = $df_stats->{$mount};
                next unless $info;
                $total = $info->{total};
                $used  = $info->{used};
                $free  = $info->{avail};
            }

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
    }

    if (!@disks && $df_stats && %$df_stats) {
        for my $mount (sort keys %$df_stats) {
            next if $seen{$mount}++;
            my $info = $df_stats->{$mount};
            next unless $info->{total};
            push @disks, {
                mount        => $mount,
                filesystem   => $info->{filesystem},
                type         => $info->{type} // 'unknown',
                total_bytes  => $info->{total},
                used_bytes   => $info->{used},
                free_bytes   => $info->{avail},
                used_pct     => _percent($info->{used}, $info->{total}),
            };
        }
    }

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

sub _df_stats {
    open my $df, '-|', 'df', '-P', '-k' or return {};
    my %stats;
    my $header = <$df>;
    while (my $line = <$df>) {
        chomp $line;
        $line =~ s/^\s+//;
        my @fields = split /\s+/, $line;
        next unless @fields >= 6;

        my $mount = pop @fields;
        my $capacity = pop @fields;    # ignored
        my $avail = pop @fields;
        my $used  = pop @fields;
        my $blocks = pop @fields;
        my $fs = join ' ', @fields;

        my $total = _maybe_number($blocks);
        my $used_bytes = _maybe_number($used);
        my $avail_bytes = _maybe_number($avail);
        next unless defined $mount && defined $total && defined $used_bytes && defined $avail_bytes;
        next unless looks_like_number($total) && looks_like_number($used_bytes) && looks_like_number($avail_bytes);

        $stats{$mount} = {
            filesystem => $fs,
            type       => 'unknown',
            total      => $total * 1024,
            used       => $used_bytes * 1024,
            avail      => $avail_bytes * 1024,
        };
    }
    close $df;
    return \%stats;
}

sub to_json {
    my ($data, %opts) = @_;
    my $encoder = JSON::PP->new->canonical->ascii(0);
    if ($opts{pretty}) {
        $encoder = $encoder->pretty;
    }
    return $encoder->encode($data);
}

sub add_human_readable_units {
    my ($data) = @_;
    return $data unless ref $data eq 'HASH';

    if (my $system = $data->{system}) {
        if (ref $system eq 'HASH' && exists $system->{uptime_sec}) {
            my $human = _human_duration($system->{uptime_sec});
            $system->{uptime_human} = $human if defined $human;
        }
    }

    if (my $mem = $data->{mem}) {
        if (ref $mem eq 'HASH') {
            _add_bytes_human($mem, qw(total_bytes available_bytes used_bytes free_bytes buffers_bytes cached_bytes));
            if (my $swap = $mem->{swap}) {
                if (ref $swap eq 'HASH') {
                    _add_bytes_human($swap, qw(total_bytes used_bytes free_bytes));
                }
            }
        }
    }

    if (my $disk = $data->{disk}) {
        if (ref $disk eq 'ARRAY') {
            for my $entry (@$disk) {
                next unless ref $entry eq 'HASH';
                _add_bytes_human($entry, qw(total_bytes used_bytes free_bytes));
            }
        }
    }

    if (my $net = $data->{net}) {
        if (ref $net eq 'ARRAY') {
            for my $iface (@$net) {
                next unless ref $iface eq 'HASH';
                _add_bytes_human($iface, qw(rx_bytes tx_bytes));
            }
        }
    }

    return $data;
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

sub _add_bytes_human {
    my ($hash, @fields) = @_;
    for my $field (@fields) {
        next unless exists $hash->{$field};
        my $value = $hash->{$field};
        my $human = _human_bytes($value);
        $hash->{ $field . '_human' } = $human if defined $human;
    }
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

sub _run_sysctl {
    my ($key) = @_;
    return undef unless defined $key && length $key;
    my $output = qx{sysctl -n $key 2>/dev/null};
    return undef if $? != 0;
    $output =~ s/^\s+//;
    $output =~ s/\s+$//;
    return undef unless length $output;
    return _maybe_number($output);
}

sub _vm_stat_pages {
    my %stats;
    my $output = qx{vm_stat 2>/dev/null};
    return %stats if $? != 0;
    for my $line (split /\n/, $output) {
        next unless $line =~ /^([^:]+):\s+(\d+)/;
        my ($key, $value) = ($1, $2);
        $key =~ s/\s+$//;
        $stats{$key} = $value;
    }
    return %stats;
}

sub _sysctl_swap_usage {
    my $output = qx{sysctl vm.swapusage 2>/dev/null};
    return (0, 0, 0) if $? != 0;

    my ($total) = $output =~ /total = ([^,]+)/;
    my ($used)  = $output =~ /used = ([^,]+)/;
    my ($free)  = $output =~ /free = ([^,\s]+)/;

    return (
        _parse_size_with_units($total),
        _parse_size_with_units($used),
        _parse_size_with_units($free),
    );
}

sub _parse_size_with_units {
    my ($value) = @_;
    return 0 unless defined $value;
    $value =~ s/^\s+//;
    $value =~ s/\s+$//;
    return 0 unless length $value;

    if ($value =~ /^([0-9]+(?:\.[0-9]+)?)\s*([KMGTPEZY]?)(i?)B/i) {
        my ($num, $unit, $binary) = ($1, uc($2 // ''), $3 // '');
        my %pow = (
            '' => 0,
            K  => 1,
            M  => 2,
            G  => 3,
            T  => 4,
            P  => 5,
            E  => 6,
            Z  => 7,
            Y  => 8,
        );
        my $exp = $pow{$unit} // 0;
        my $base = $binary ? 1024 : 1000;
        my $bytes = ($num + 0) * ($base ** $exp);
        return int($bytes + 0.5);
    }

    return _maybe_number($value) // 0;
}

sub _human_bytes {
    my ($value) = @_;
    return undef unless defined $value && looks_like_number($value);

    my $bytes = $value + 0;
    my @units = qw(B KiB MiB GiB TiB PiB EiB ZiB YiB);
    my $idx = 0;
    while (abs($bytes) >= 1024 && $idx < $#units) {
        $bytes /= 1024;
        $idx++;
    }

    my $format = ($idx == 0 || abs($bytes) >= 10) ? '%.0f %s' : '%.1f %s';
    return sprintf($format, $bytes, $units[$idx]);
}

sub _human_duration {
    my ($seconds) = @_;
    return undef unless defined $seconds && looks_like_number($seconds);

    my $remaining = int($seconds + 0.5);
    $remaining = 0 if $remaining < 0;

    my @units = (
        [86400, 'd'],
        [3600,  'h'],
        [60,    'm'],
        [1,     's'],
    );
    my @parts;
    for my $unit (@units) {
        my ($size, $label) = @$unit;
        next if $remaining < $size && $label ne 's' && !@parts;
        my $value = int($remaining / $size);
        if ($value > 0) {
            push @parts, $value . $label;
            $remaining -= $value * $size;
        } elsif ($label eq 's' && !@parts) {
            push @parts, '0s';
        }
    }

    return join ' ', @parts;
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

=head1 FUNCTIONS

=head2 collect_all

    my $data = Sys::Monitor::Lite::collect_all();

Collects all available metrics and returns a hash reference keyed by
metric name. This is a convenience wrapper around L</collect> with no
arguments.

=head2 collect

    my $subset = Sys::Monitor::Lite::collect(['cpu', 'mem']);

Collects the metrics listed in the array reference (or list). Unknown
metrics are ignored. The returned value matches the structure of
L</collect_all> but contains only the requested keys.

=head2 available_metrics

    my @names = Sys::Monitor::Lite::available_metrics();

Returns a sorted list of metric names that the module can collect.

=head2 to_json

    my $json = Sys::Monitor::Lite::to_json($data, pretty => 1);

Serialises the supplied data structure to a JSON string using
L<JSON::PP>. Pass C<pretty =E<gt> 1> to enable human-readable output.

=head2 add_human_readable_units

    Sys::Monitor::Lite::add_human_readable_units($data);

Enhances the collected metrics by adding keys that express byte counts
and uptime values in a human-readable manner. Numeric fields remain
untouched while additional keys suffixed with C<_human> (or
C<uptime_human>) are added alongside them.

=head1 EXPORT

This module does not export any symbols by default. Functions can be
called with their fully-qualified names, e.g. C<Sys::Monitor::Lite::collect_all()>.

=head1 SEE ALSO

L<script/sys-monitor-lite> – command-line interface for this module.

=head1 AUTHOR

Shingo Kawamura E<lt>kpannakoota1@gmail.comE<gt>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2025 by Shingo Kawamura.

This is free software; you can redistribute it and/or modify it under
the same terms as the MIT license included with this distribution.


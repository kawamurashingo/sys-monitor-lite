use strict;
use warnings;
use Test::More;
use JSON::PP;
use File::Spec;
use Sys::Monitor::Lite;

subtest 'available metrics' => sub {
    my @metrics = Sys::Monitor::Lite::available_metrics();
    is_deeply(\@metrics, [qw(cpu disk load mem net system)], 'expected metric list');
};

subtest 'collect_all structure' => sub {
    my $data = Sys::Monitor::Lite::collect_all();
    isa_ok($data, 'HASH', 'collect_all returns hashref');
    ok($data->{timestamp}, 'timestamp present');

    for my $key (qw(system cpu load mem disk net)) {
        ok(exists $data->{$key}, "$key metric present");
    }

    isa_ok($data->{system}, 'HASH', 'system data');
    isa_ok($data->{cpu}, 'HASH', 'cpu data');
    isa_ok($data->{load}, 'HASH', 'load data');
    isa_ok($data->{mem}, 'HASH', 'mem data');
    isa_ok($data->{disk}, 'ARRAY', 'disk data');
    ok(@{ $data->{disk} } >= 1, 'at least one disk entry collected');
    my $disk = $data->{disk}[0];
    isa_ok($disk, 'HASH', 'disk entry structure');
    for my $field (qw(mount filesystem type total_bytes used_bytes free_bytes used_pct)) {
        ok(exists $disk->{$field}, "disk entry has $field");
    }
    isa_ok($data->{net}, 'ARRAY', 'net data');
};

subtest 'human readable augmentation' => sub {
    my $data = Sys::Monitor::Lite::collect_all();
    Sys::Monitor::Lite::add_human_readable_units($data);

    ok($data->{system}{uptime_human}, 'uptime_human present');
    like($data->{mem}{total_bytes_human} // '', qr/\b[KMGTPEZY]?i?B\b/, 'mem total human readable');
    like($data->{mem}{swap}{total_bytes_human} // '', qr/\b[KMGTPEZY]?i?B\b/, 'swap total human readable');

    if (@{ $data->{disk} }) {
        ok($data->{disk}[0]{total_bytes_human}, 'disk human readable field added');
    } else {
        pass('no disk entries to test human readable conversion');
    }

    if (@{ $data->{net} }) {
        ok(exists $data->{net}[0]{rx_bytes_human}, 'net human readable field added');
    } else {
        pass('no network entries to test human readable conversion');
    }
};

subtest 'selective collect' => sub {
    my $data = Sys::Monitor::Lite::collect(['system', 'cpu']);
    isa_ok($data, 'HASH', 'collect returns hashref');
    is_deeply([sort grep { $_ ne 'timestamp' } keys %$data], [qw(cpu system)], 'only requested metrics collected');
};

subtest 'json encoding' => sub {
    my $json = Sys::Monitor::Lite::to_json({ foo => 'bar' });
    my $decoded = JSON::PP->new->decode($json);
    is($decoded->{foo}, 'bar', 'default JSON roundtrip');

    my $pretty = Sys::Monitor::Lite::to_json({ foo => 'bar' }, pretty => 1);
    like($pretty, qr/\n/, 'pretty JSON contains newline');
};

subtest 'cli integration' => sub {
    my $perl = $^X;
    my $script = File::Spec->catfile('script', 'sys-monitor-lite');
    my $output = qx{$perl $script --once --collect system --output json};
    ok($? == 0, 'cli exited successfully');

    my $decoded = eval { JSON::PP->new->decode($output) };
    ok(!$@, 'cli output is valid JSON');
    isa_ok($decoded->{system}, 'HASH', 'cli returned system data');

    my $human_output = qx{$perl $script --once --collect mem --output json --human};
    ok($? == 0, 'cli exited successfully with --human');
    my $decoded_human = eval { JSON::PP->new->decode($human_output) };
    ok(!$@, 'cli --human output is valid JSON');
    like($decoded_human->{mem}{total_bytes_human} // '', qr/\b[KMGTPEZY]?i?B\b/, '--human output contains human readable value');
};
# ensure subtests run before done_testing

# done_testing automatically counts subtests

done_testing();

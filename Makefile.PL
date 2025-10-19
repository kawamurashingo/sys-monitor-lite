use ExtUtils::MakeMaker;

WriteMakefile(
    NAME         => 'Sys::Monitor::Lite',
    VERSION_FROM => 'lib/Sys/Monitor/Lite.pm',
    ABSTRACT     => 'Lightweight system monitoring toolkit with JSON output',
    AUTHOR       => 'Shingo Kawamura',
    LICENSE      => 'mit',
    EXE_FILES    => ['script/sys-monitor-lite'],
);


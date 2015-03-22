use strict; use warnings FATAL => 'all';
use Test::More;

# Ported from Dist::Zilla::Plugin::CheckLib (C) 2014 Karen Etheridge

use Test::DZil;
use Test::Deep;
use Test::Fatal;
use Test::Warnings;

use Path::Tiny;

my $tzil = Builder->from_config(
    { dist_root => 't/does-not-exist' },
    {
        add_files => {
            path(qw(source dist.ini)) => simple_ini(
                [ GatherDir => ],
                [ MetaConfig => ],
                [ 'MakeMaker' => ],
                [ 'CheckPerlSymbols' => {
                        has_symbol => [ 'foo $^O eq "linux"', 'bar' ],
                        lacks_symbol => 'baz $^O =~ /bsd$/i',
                    },
                ],
            ),
            path(qw(source lib Foo.pm)) => "package Foo;\n1;\n",
        },
    },
);

$tzil->chrome->logger->set_debug(1);
is(
    exception { $tzil->build },
    undef,
    'nothing exploded',
);

my $build_dir = path($tzil->tempdir)->child('build');
my $file = $build_dir->child('Makefile.PL');
ok(-e $file, 'Makefile.PL created');

my $content = $file->slurp_utf8;
unlike($content, qr/[^\S\n]\n/m, 'no trailing whitespace in generated file');

my $version = Dist::Zilla::Plugin::CheckPerlSymbols->VERSION || '<self>';

my $pattern = <<PATTERN;
use strict;
use warnings;

# inserted by Dist::Zilla::Plugin::CheckPerlSymbols $version
use FFI::Platypus;
my \$ffi = FFI::Platypus->new;
\$ffi->lib(undef);
if (\$^O eq "linux" && !\$ffi->find_symbol('foo')) {
  warn "Required native symbol 'foo' not found in running perl; installation can't continue.\\n"; exit
}
unless (\$ffi->find_symbol('bar')) {
  warn "Required native symbol 'bar' not found in running perl; installation can't continue.\\n"; exit
}
if (\$^O =~ /bsd\$/i && \$ffi->find_symbol('baz')) {
  warn "Conflicting native symbol 'baz' found in running perl; installation can't continue.\\n"; exit
}
PATTERN

like(
    $content,
    qr/^\Q$pattern\E$/m,
    'code inserted into Makefile.PL',
);

cmp_deeply(
    $tzil->distmeta,
    superhashof({
        prereqs => superhashof({
            configure => {
                requires => {
                    'FFI::Platypus' => '0.32',
                    'ExtUtils::MakeMaker' => ignore,    # populated by [MakeMaker]
                },
            },
            # build prereqs go here
        }),
        x_Dist_Zilla => superhashof({
            plugins => supersetof(
                {
                    class => 'Dist::Zilla::Plugin::CheckPerlSymbols',
                    config => {
                        'Dist::Zilla::Plugin::CheckPerlSymbols' => superhashof({
                            has_symbol   => [ 'foo $^O eq "linux"', 'bar' ],
                            lacks_symbol => [ 'baz $^O =~ /bsd$/i' ],
                        }),
                    },
                    name => 'CheckPerlSymbols',
                    version => ignore,
                },
            ),
        }),
    }),
    'prereqs are properly injected for the configure phase',
) or diag 'got distmeta: ', explain $tzil->distmeta;

diag 'got log messages: ', explain $tzil->log_messages
    if not Test::Builder->new->is_passing;

done_testing;

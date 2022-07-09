package App::orgadb::Select::Shell::Commands;

use 5.010001;
use strict;
use warnings;
use Log::ger;

# AUTHORITY
# DATE
# DIST
# VERSION

use App::orgadb::Common;

our %SPEC;

$SPEC{':package'} = {
    v => 1.1,
    summary => 'orgadb-sel shell commands',
};

$SPEC{history} = {
    v => 1.1,
    summary => 'Show shell history',
    args => {
        append => {
            summary    => "Append current session's history to history file",
            schema     => 'bool',
            cmdline_aliases => { a=>{} },
        },
        read => {
            summary    => '(Re-)read history from file',
            schema     => 'bool',
            cmdline_aliases => { r=>{} },
        },
        clear => {
            summary    => 'Clear history',
            schema     => 'bool',
            cmdline_aliases => { c=>{} },
        },
    },
};
sub history {
    my %args = @_;
    my $shell = $args{-shell};

    if ($args{add}) {
        $shell->save_history;
        return [200, "OK"];
    } elsif ($args{read}) {
        $shell->load_history;
        return [200, "OK"];
    } elsif ($args{clear}) {
        $shell->clear_history;
        return [200, "OK"];
    } else {
        my @history;
        if ($shell->{term}->Features->{getHistory}) {
            @history = grep { length } $shell->{term}->GetHistory;
        }
        return [200, "OK", \@history,
                {"x.app.riap.default_format"=>"text-simple"}];
    }
}

$SPEC{select} = {
    v => 1.1,
    summary => 'Select entries/fields/subfields',
    args => {
        %App::orgadb::Common::argspecs_select,
    },
};
sub select {
    my %args = @_;
    my $shell = $args{-shell};

    my $code_parse_files = $args{_code_parse_files};

    # XXX currently when one file changes mtime, all files are reloaded
    my $files = $shell->state('main_args')->{files};
    my $should_reload;
    {
        my $file_mtimes = $shell->state('file_mtimes');
        unless ($file_mtimes) {
            $file_mtimes = [];
            $shell->state('file_mtimes', $file_mtimes);
        }
        for my $i (0 .. $#{$files}) {
            my $file = $files->[$i];
            my $cur_mtime = -M $file;
            my $last_mtime = $file_mtimes->[$i];
            if (!$last_mtime || $cur_mtime != $last_mtime) {
                $should_reload++;
            }
            $file_mtimes->[$i] = $cur_mtime;
        }
    }

    if ($should_reload) {
        my ($trees, $tree_filenames) =
            $shell->state('main_args')->{_code_parse_files}->(@$files);

        $shell->state(trees => $trees);
        $shell->state(tree_filenames => $tree_filenames);
    }

    App::orgadb::_select_single(
        %{ $shell->{_state}{main_args} },
        _trees => $shell->state('trees'),
        _tree_filenames => $shell->state('tree_filenames'),
        %args,
    );
}

1;
# ABSTRACT:

=for Pod::Coverage .+

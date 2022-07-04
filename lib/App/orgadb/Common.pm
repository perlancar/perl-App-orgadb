package App::orgadb::Common;

use 5.010001;
use strict;
use warnings;
use Log::ger;

# AUTHORITY
# DATE
# DIST
# VERSION

our %argspecs_common = (
    files => {
        summary => 'Path to addressbook files',
        'summary.alt.plurality.singular' => 'Path to addressbook file',
        'x.name.is_plural' => 1,
        'x.name.singular' => 'file',
        schema => ['array*', of=>'filename*', min_len=>1],
        cmdline_aliases=>{f=>{}},
        tags => ['category:input'],
    },
    shell => {
        schema => 'true*',
        cmdline_aliases=>{s=>{}},
        tags => ['category:mode'],
    },
    reload_files_on_change => {
        schema => 'bool*',
        default => 1,
    },
    color => {
        summary => 'Whether to use color',
        schema => ['str*', in=>[qw/auto always never/]],
        default => 'auto',
        tags => ['category:color'],
    },
    color_theme => {
        schema => 'perl::colortheme::modname_with_optional_args*',
        tags => ['category:color'],
    },
);

our %argspecopt_category = (
    category => {
        summary => 'Find entry by string or regex search against the category title',
        schema => 'str_or_re*',
        cmdline_aliases=>{c=>{}},
        tags => ['category:filter'],
    },
);

our %argspecopt0_entry = (
    entry => {
        summary => 'Find entry by string or regex search against its title',
        schema => 'str_or_re*',
        pos => 0,
        tags => ['category:filter'],
    },
);

our %argspecopt1_field = (
    fields => {
        'x.name.is_plural' => 1,
        'x.name.singular' => 'field',
        summary => 'Find (sub)fields by string or regex search',
        schema => ['array*', of=>'str_or_re*'],
        pos => 1,
        slurpy => 1,
        tags => ['category:filter'],
    },
);

our %argspecs_select = (
    %argspecopt0_entry,
    %argspecopt1_field,
    %argspecopt_category,
    hide_category => {
        summary => 'Do not show category',
        schema => 'true*',
        cmdline_aliases => {C=>{}},
        tags => ['category:display'],
    },
    hide_entry => {
        summary => 'Do not show entry headline',
        schema => 'true*',
        cmdline_aliases => {E=>{}},
        tags => ['category:display'],
    },
    hide_field_name => {
        summary => 'Do not show field names, just show field values',
        schema => 'true*',
        cmdline_aliases => {N=>{}},
        tags => ['category:display'],
    },
    detail => {
        schema => 'bool*',
        cmdline_aliases => {l=>{}},
        tags => ['category:display'],
    },
    formatters => {
        'x.name.is_plural' => 1,
        'x.name.singular' => 'formatter',
        summary => 'Add one or more formatters to display field value',
        schema => ['array*', of=>'str*'],
        tags => ['category:display'],
        description => <<'_',

Specify one or more formatters to apply to the field value before displaying.

A formatter is name of `Data::Sah::Filter::perl::*` module, without the prefix.
For example: `Str::uc` will convert the field value to uppercase. Another
formatter, `Str::remove_comment` can remove comment.

A formatter can have arguments, which is specified using this format:

    [FORMATTER_NAME, {ARG1NAME => ARG1VAL, ...}]

If formatter name begins with `[` character, it will be parsed as JSON. Example:

 ['Str::remove_comment', {'style':'cpp'}]


_
    },

    num_entries => {
        summary => 'Specify maximum number of entries to return (0 means unlimited)',
        schema => 'uint*',
        tags => ['category:result'],
    },
    num_fields => {
        summary => 'Specify maximum number of fields (per entry) to return (0 means unlimited)',
        schema => 'uint*',
        tags => ['category:result'],
    },
);

1;
# ABSTRACT:

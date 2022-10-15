package App::orgadb::Common;

use 5.010001;
use strict;
use warnings;
use Log::ger;

# AUTHORITY
# DATE
# DIST
# VERSION

sub _heading_from_line {
    my $heading = shift;

    # string tags
    $heading =~ s/(.+?)\s+:(?:\w+:)+\z/$1/;
    # XXX strip radio target, todo keywords, count cookies

    $heading;
}

sub _complete_category {
    my %args = @_;

    my $word = $args{word} // '';

    # only run under pericmd
    my $cmdline = $args{cmdline} or return;
    my $r = $args{r};

    # force read config file, because by default it is turned off when in
    # completion
    $r->{read_config} = 1;
    my $parse_res = $cmdline->parse_argv($r);
    my $cli_args = $parse_res->[2];

    # read all heading lines from all files
    my @l1_headings;
    {
        last unless $cli_args->{files} && @{ $cli_args->{files} };
        for my $file (@{ $cli_args->{files} }) {
            open my $fh, "<", $file or do {
                log_trace "Addressbook file %s cannot be opened, skipped", $file;
                next;
            };
            while (my $line = <$fh>) {
                next unless $line =~ /^\* (.+)/;
                chomp(my $heading = $1);
                push @l1_headings, _heading_from_line($heading);
            }
        }
    }

    require Complete::Util;
    Complete::Util::complete_array_elem(
        array => \@l1_headings,
        word  => $word,
    );
}

sub _complete_entry {
    my %args = @_;

    my $word = $args{word} // '';

    # only run under pericmd
    my $cmdline = $args{cmdline} or return;
    my $r = $args{r};

    # force read config file, because by default it is turned off when in
    # completion
    $r->{read_config} = 1;
    my $parse_res = $cmdline->parse_argv($r);
    my $cli_args = $parse_res->[2];

    require Regexp::From::String;

    # read all heading lines from all files
    my @l2_headings;
    {
        last unless $cli_args->{files} && @{ $cli_args->{files} };
        for my $file (@{ $cli_args->{files} }) {
            open my $fh, "<", $file or do {
                log_trace "Addressbook file %s cannot be opened, skipped", $file;
                next;
            };
            my $cur_l1_heading = '';
            my $category_re;
            while (my $line = <$fh>) {
                if ($line =~ /^\* (.+)/) {
                    chomp($cur_l1_heading = _heading_from_line($1));
                    next;
                } elsif ($line =~ /^\*\* (.+)/) {
                    # if user has specified category, only consider entries that
                    # match the category
                    if (defined $cli_args->{category}) {
                        unless (defined $category_re) {
                            $category_re = Regexp::From::String::str_to_re({case_insensitive=>1}, $cli_args->{category});
                        }
                        next unless $cur_l1_heading =~ $category_re;
                    }

                    chomp(my $heading = $1);
                    push @l2_headings, _heading_from_line($heading);
                }
            }
        }
    }

    require Complete::Util;
    Complete::Util::complete_array_elem(
        array => \@l2_headings,
        word  => $word,
    );
}

sub _complete_field {
    my %args = @_;

    my $word = $args{word} // '';

    # only run under pericmd
    my $cmdline = $args{cmdline} or return;
    my $r = $args{r};

    # force read config file, because by default it is turned off when in
    # completion
    $r->{read_config} = 1;
    my $parse_res = $cmdline->parse_argv($r);
    my $cli_args = $parse_res->[2];

    unless (defined $cli_args->{entry}) {
        return {message=>"Please specify entry first", static=>1};
    }

    require Regexp::From::String;

    # read all heading lines from all files
    my @fields;
    {
        last unless $cli_args->{files} && @{ $cli_args->{files} };
        for my $file (@{ $cli_args->{files} }) {
            open my $fh, "<", $file or do {
                log_trace "Addressbook file %s cannot be opened, skipped", $file;
                next;
            };
            my $cur_l1_heading = '';
            my $cur_l2_heading = '';
            my $category_re;
            my $entry_re = Regexp::From::String::str_to_re({case_insensitive=>1}, $cli_args->{entry});
            while (my $line = <$fh>) {
                if ($line =~ /^\* (.+)/) {
                    chomp($cur_l1_heading = $1);
                    # XXX strip radio target, tags, todo keywords, count cookies
                    next;
                } elsif ($line =~ /^\*\* (.+)/) {
                    # if user has specified category, only consider entries that
                    # match the category
                    if (defined $cli_args->{category}) {
                        unless (defined $category_re) {
                            $category_re = Regexp::From::String::str_to_re({case_insensitive=>1}, $cli_args->{category});
                        }
                        next unless $cur_l1_heading =~ $category_re;
                    }

                    chomp($cur_l2_heading = $1);
                    # XXX strip radio target, tags, todo keywords, count cookies
                    next;
                } elsif ($line =~ /^\s*[+*-]\s+(.+?)\s+::/) {
                    my $field = $1;

                    # only consider field under the matching category & entry
                    if (defined $category_re) {
                        next unless $cur_l1_heading =~ $category_re;
                    }
                    next unless defined $entry_re;
                    next unless $cur_l2_heading =~ $entry_re;

                    push @fields, $field;
                }
            }
        }
    }

    require Complete::Util;
    Complete::Util::complete_array_elem(
        array => \@fields,
        word  => $word,
    );
}

our %argspecs_common = (
    files => {
        summary => 'Path to addressbook files',
        'summary.alt.plurality.singular' => 'Path to addressbook file',
        'x.name.is_plural' => 1,
        'x.name.singular' => 'file',
        schema => ['array*', of=>'filename*', min_len=>1],
        'x.element_completion' => ['filename', {file_ext_filter=>[qw/org ORG/]}],
        tags => ['category:input'],
    },
    reload_files_on_change => {
        schema => 'bool*',
        default => 1,
        tags => ['category:input'],
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

    shell => {
        schema => 'true*',
        cmdline_aliases=>{s=>{}},
        tags => ['category:mode'],
    },
);

our %argspecopt_category = (
    category => {
        summary => 'Find entry by string or regex search against the category title',
        schema => 'str_or_re*',
        cmdline_aliases=>{c=>{}},
        completion => \&_complete_category,
        tags => ['category:filter'],
    },
);

our %argspecopt0_entry = (
    entry => {
        summary => 'Find entry by string or regex search against its title',
        schema => 'str_or_re*',
        pos => 0,
        completion => \&_complete_entry,
        tags => ['category:entry-selection'],
    },
);

our %argspecopt_filter_entry_by_fields = (
    filter_entries_by_fields => {
        'x.name.is_plural' => 1,
        'x.name.singular' => 'filter_entries_by_field',
        summary => 'Find entry by the fields or subfields it has',
        schema => ['array*', of=> 'str*'],
        tags => ['category:entry-selection'],
        description => <<'_',

The format of each entry_by_field is one of:

    str
    /re/
    str = str2
    str = /re2/
    /re/ = str2
    /re/ = /re2/

That is, it can search for a string (`str`) or regex (`re`) in the field name,
and optionally also search for a string (`str2`) or regex (`re2`) in the field
value.

_
    },
);

our %argspecopt1_field = (
    fields => {
        summary => 'Find (sub)fields by string or regex search',
        'x.name.is_plural' => 1,
        'x.name.singular' => 'field',
        schema => ['array*', of=>'str_or_re*'],
        pos => 1,
        slurpy => 1,
        element_completion => \&_complete_field,
        tags => ['category:field-selection'],
    },
);

our %argspecs_select = (

    %argspecopt0_entry,

    %argspecopt_category,

    %argspecopt1_field,
    %argspecopt_filter_entry_by_fields,

    hide_category => {
        summary => 'Do not show category',
        schema => 'true*',
        cmdline_aliases => {C=>{}},
        tags => ['category:output'],
    },
    hide_entry => {
        summary => 'Do not show entry headline',
        schema => 'true*',
        cmdline_aliases => {E=>{}},
        tags => ['category:output'],
    },
    hide_field_name => {
        summary => 'Do not show field names, just show field values',
        schema => 'true*',
        cmdline_aliases => {N=>{}},
        tags => ['category:output'],
    },
    detail => {
        schema => 'bool*',
        cmdline_aliases => {l=>{}},
        tags => ['category:output'],
    },
    count => {
        summary => 'Return just the number of matching entries instead of showing them',
        schema => 'true*',
    },
    no_formatters => {
        summary => 'Do not apply any formatters to field value (overrides --formatter option)',
        schema => 'true*',
        description => <<'_',

Note that this option has higher precedence than `--default-formatter-rules` or
the `--formatter` option.

_
        cmdline_aliases => {raw_field_values=>{}, F=>{}},
        tags => ['category:output'],
    },
    default_formatter_rules => {
        'x.name.is_plural' => 1,
        'x.name.singular' => 'default_formatter_rule',
        schema => ['array*', of=>'hash*'],
        description => <<'_',

Specify conditional default formatters, as an array of hashes. Each element is a
rule that is specified as a hash containing condition keys and formatters keys.
If all conditions are met then the formatters will be applied. The rules will be
tested when each field is about to be outputted. Multiple rules can match and
the matching rules' formatters are all applied in succession.

Note that this option will be overridden by the `--formatter` or the
`--no-formatters` (`-F`) option.

Default formatters are best specified in the configuration as opposed to on the
command-line option. An example (the lines below are writen in configuration
file in IOD syntax, as rows of JSON hashes):

    ; by default remove all comments in field values when 'hide_field_name'
    ; option is set (which usually means we want to copy paste things)
    default_formatter_rules={"hide_field_name":true, "formatters":[ ["Str::remove_comment"] ]}

    ; by default normalize phone numbers using Phone::format_phone_idn_nospace
    ; when 'hide_field_name' option is set (which usually means we want to copy
    ; paste things). e.g. '0812-1234-5678' becomes '+6281212345678'.
    default_formatter_rules={"field_name_matches":"/phone|wa|whatsapp/i", "hide_field_name":true, "formatters":[ ["Phone::format_phone_idn_nospace"] ]}

    ; but if 'hide_field_name' field is not set, normalize phone numbers using
    ; Phone::format_phone_idn which is more easier to see (e.g. '+62 812 1234
    ; 5678').
    default_formatter_rules={"field_name_matches":"/phone|wa|whatsapp/i", "hide_field_name":false, "formatters":[ ["Phone::format_phone_idn_nospace"] ]}

Condition keys:

* `field_name_matches` (value: str/re): Check if field name matches a regex pattern.

* `hide_field_name` (value: bool): Check if `--hide-field-name` (`-N`) option is
  set (true) or unset (false).

Formatter keys:

* `formatters`: an array of formatters, to be applied. Each formatter is a name
  of perl Sah filter rule, or a two-element array of perl Sah filter rule name
  followed by hash containing arguments. See `--formatter` for more detais on
  specifying formatter.

_
        tags => ['category:output'],
    },
    formatters => {
        'x.name.is_plural' => 1,
        'x.name.singular' => 'formatter',
        summary => 'Add one or more formatters to display field value',
        #schema => ['array*', of=>'perl::perl_sah_filter::modname_with_optional_args*'], ## doesn't work yet with Perinci::Sub::GetArgs::Argv
        schema => ['array*', of=>'str*'],
        element_completion => sub {
            require Complete::Module;
            my %args = @_;
            Complete::Module::complete_module(
                word => $args{word},
                ns_prefix => 'Data::Sah::Filter::perl',
            );
        },
        cmdline_aliases => {f=>{}},
        tags => ['category:output'],
        description => <<'_',

Specify one or more formatters to apply to the field value before displaying.

A formatter is name of `Data::Sah::Filter::perl::*` module, without the prefix.
For example: `Str::uc` will convert the field value to uppercase. Another
formatter, `Str::remove_comment` can remove comment.

A formatter can have arguments, which is specified using this format:

    [FORMATTER_NAME, {ARG1NAME => ARG1VAL, ...}]

If formatter name begins with `[` character, it will be parsed as JSON. Example:

 ['Str::remove_comment', {'style':'cpp'}]

Note that this option verrides `--default-formatter-rules` but overridden by the
`--no-formatters` (`--raw-field-values`, `-F`) option.

_
    },

    num_entries => {
        summary => 'Specify maximum number of entries to return (0 means unlimited)',
        schema => 'uint*',
        tags => ['category:output'],
    },
    num_fields => {
        summary => 'Specify maximum number of fields (per entry) to return (0 means unlimited)',
        schema => 'uint*',
        tags => ['category:output'],
    },

    clipboard => {
        summary => 'Whether to copy matching field values to clipboard',
        schema => ['str*', in=>[qw/tee only/]],
        description => <<'_',

If set to `tee`, then will display matching fields to terminal as well as copy
matching field values to clipboard.

If set to `only`, then will not display matching fields to terminal and will
only copy matching field values to clipboard.

_
        cmdline_aliases => {
            clipboard_only => {is_flag=>1, summary=>'Alias for --clipboard=only', code=>sub { $_[0]{clipboard} = 'only' }},
        },
        tags => ['category:output'],
    },
);

1;
# ABSTRACT:

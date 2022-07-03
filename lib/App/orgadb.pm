package App::orgadb;

use 5.010001;
use strict;
use warnings;
use Log::ger;

# AUTHORITY
# DATE
# DIST
# VERSION

our %SPEC;

$SPEC{':package'} = {
    v => 1.1,
    summary => 'An opinionated Org addressbook tool',
};

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
    shell_mode => {
        schema => 'true*',
        cmdline_aliases=>{s=>{}},
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
        cmdline_aliases => {F=>{}},
        tags => ['category:display'],
    },
    detail => {
        schema => 'bool*',
        cmdline_aliases => {l=>{}},
        tags => ['category:display'],
    },
);

sub _highlight {
    my ($clrtheme_obj, $re, $text) = @_;
    return $text unless $clrtheme_obj && $re;

    require ColorThemeUtil::ANSI;
    my $ansi_highlight = ColorThemeUtil::ANSI::item_color_to_ansi($clrtheme_obj->get_item_color('highlight'));
    $text =~ s/($re)/$ansi_highlight$1\e[0m/g;
    $text;
}

# this is like select_addressbook_entries(), but selects from object trees
# instead of from an Org file.
sub _select_addressbook_entries {
    my %args = @_;

    my $trees = $args{_trees};
    my $tree_filenames = $args{_tree_filenames};

    my $res = [200, "OK", ""];

    my @matching_entries;
    my ($re_category, $re_entry, $re_field);
  FIND_ENTRIES: {
        require Data::CSel;
        require Data::Dmp;

        my $expr = '';

        if (defined $args{category}) {
            $expr .= 'Headline[level=1][title.text';
            if (ref $args{category} eq 'Regexp') {
                $re_category = $args{category};
            } else {
                $re_category = quotemeta($args{category});
                $re_category = qr/$re_category/;
            }
            $expr .= " =~ " . Data::Dmp::dmp($re_category) . "]";
        }

        $expr .= (length $expr ? " " : "") . 'Headline[level=2]';
        if (defined $args{entry}) {
            $expr .= '[title.text';
            if (ref $args{entry} eq 'Regexp') {
                $re_entry = $args{entry};
            } else {
                $re_entry = quotemeta($args{entry});
                $re_entry = qr/$re_entry/;
            }
            $expr .= " =~ " . Data::Dmp::dmp($re_entry) . "]";
        }

        log_trace "CSel expression: <$expr>";
        #log_trace "Number of trees: %d", scalar(@trees);

        for my $tree (@$trees) {
            my @nodes = Data::CSel::csel({
                class_prefixes => ["Org::Element"],
            }, $expr, $tree);
            push @matching_entries, @nodes;
        }
    } # FIND_ENTRIES
    log_trace "Number of matching entries: %d", scalar(@matching_entries);

  DISPLAY_ENTRIES: {
        my ($clrtheme, $clrtheme_obj);
      LOAD_COLOR_THEME: {
            my $color = $args{color} // 'auto';
            my $use_color =
                ($color eq 'always' ? 1 : $color eq 'never' ? 0 : undef) //
                (defined $ENV{NO_COLOR} ? 0 : undef) //
                ($ENV{COLOR} ? 1 : defined($ENV{COLOR}) ? 0 : undef) //
                (-t STDOUT); ## no critic: InputOutput::ProhibitInteractiveTest
            last unless $use_color;
            require Module::Load::Util;
            $clrtheme = $args{color_them} // $ENV{ORGADB_COLOR_THEME} // 'Light';
            $clrtheme_obj = Module::Load::Util::instantiate_class_with_optional_args(
                {ns_prefixes=>['ColorTheme::Search','ColorTheme','']}, $clrtheme);
        };

        my ($expr_field, @re_field);
      ENTRY:
        for my $entry (@matching_entries) {

            my @matching_fields;
            if (defined($args{fields}) && @{ $args{fields} }) {
                unless (defined $expr_field) {
                    $expr_field = '';
                    for my $field_term (@{ $args{fields} }) {
                        $expr_field .= ' ' if $expr_field;
                        $expr_field .= 'ListItem[desc_term.text';
                        my $re_field;
                        if (ref $field_term eq 'Regexp') {
                            $re_field = $field_term;
                        } else {
                            $re_field = quotemeta($field_term);
                            $re_field = qr/$re_field/;
                        }
                        $expr_field .= " =~ " . Data::Dmp::dmp($re_field) . "]";
                        push @re_field, $re_field;
                    }
                }

                @matching_fields = Data::CSel::csel({
                    class_prefixes => ["Org::Element"],
                }, $expr_field, $entry);

                next ENTRY unless @matching_fields;
            }

            unless ($args{hide_entry}) {
                $res->[2] .= "** ";
                unless ($args{hide_category}) {
                    $res->[2] .= _highlight(
                        $clrtheme_obj,
                        $re_category,
                        $entry->parent->title->text) . "/";
                }
                $res->[2] .= _highlight(
                    $clrtheme_obj,
                    $re_entry,
                    $entry->title->text,
                );
                $res->[2] .= "\n";
            }

            my $re_field;
            $re_field = join "|", @re_field if @re_field;
            if ($args{detail} || ( !defined($args{fields} || !@{$args{fields}} ))) {
                my $str = $entry->children_as_string;
                $str = _highlight(
                    $clrtheme_obj,
                    $re_field,
                    $str) if defined $re_field;
                $res->[2] .= $str;
            } elsif (@matching_fields) {
                for my $field (@matching_fields) {

                    unless ($args{hide_field_name}) {
                        my $field_name = '';
                        $field_name = _highlight(
                            $clrtheme_obj,
                            $re_field,
                            $field->bullet . ' ' . $field->desc_term->text,
                        ) . " ::";
                        $res->[2] .= $field_name;
                    }

                    my $field_value = $field->children_as_string;
                    $field_value =~ s/\A\s+//s if $args{hide_field_name};
                    $res->[2] .= $field_value;
                }
            }
        }
    }

    $res;
}

$SPEC{select_addressbook_entries} = {
    v => 1.1,
    summary => 'Select Org addressbook entries/fields/subfields',
    args => {
        %argspecs_common,
        %argspecs_select,
    },
    'x.envs' => {
        'ORGADB_COLOR_THEME' => {
            summary => 'Set default color theme',
            schema => 'perl::colortheme::modname_with_optional_args*',
            description => <<'_',

Color theme is Perl module name under the `ColorTheme::Search::` namespace,
without the namespace prefix. The default is `Light`. You can set color theme
using the `--color-theme` command-line option as well as this environment
variable.

_
        },
    },
};
sub select_addressbook_entries {
    my %args = @_;

    my @trees;
    my @tree_filenames;
  PARSE_FILES: {
        require Org::Parser;
        my $parser = Org::Parser->new;

        for my $filename (@{ delete $args{files} }) {
            my $doc;
            if ($filename eq '-') {
                binmode STDIN, ":encoding(utf8)";
                $doc = $parser->parse(join "", <>);
            } else {
                local $ENV{PERL_ORG_PARSER_CACHE} = $ENV{PERL_ORG_PARSER_CACHE} // 1;
                $doc = $parser->parse_file($filename);
            }
            push @trees, $doc;
            push @tree_filenames, $filename;
        } # for filename
    } # PARSE_FILES

    _select_addressbook_entries(
        %args,
        _trees => \@trees,
        _tree_filenames => \@tree_filenames,
    );
}
1;
#ABSTRACT:

=head1 SYNOPSIS

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
        tags => ['category:input'],
    },
);

our %argspec_category = (
    entry => {
        summary => 'Find entry by string or regex search against the category title',
        schema => 'str_or_re*',
        cmdline_aliases=>{c=>{}},
    },
);

our %argspecopt0_entry = (
    entry => {
        summary => 'Find entry by string or regex search against its title',
        schema => 'str_or_re*',
        pos => 0,
    },
);

our %argspecopt1_field = (
    field => {
        summary => 'Find field by string or regex search',
        schema => 'str_or_re*',
        pos => 1,
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

$SPEC{select_addressbook_entries} = {
    v => 1.1,
    summary => 'Select Org document elements using CSel (CSS-selector-like) syntax',
    args => {
        %argspecs_common,
        %argspecopt0_entry,
        %argspecopt1_field,
        category => {
            schema => 'str_or_re*',
            cmdline_aliases=>{c=>{}},
        },
        hide_category => {
            summary => 'Do not show category',
            schema => 'true*',
            cmdline_aliases => {C=>{}},
        },
        hide_entry => {
            summary => 'Do not entry headline',
            schema => 'true*',
            cmdline_aliases => {E=>{}},
        },
        color => {
            summary => 'Whether to use color',
            schema => ['str*', in=>[qw/auto always never/]],
            default => 'auto',
        },
        color_theme => {
            schema => 'perl::colortheme::modname_with_optional_args*',
        },
        detail => {
            schema => 'bool*',
            cmdline_aliases => {l=>{}},
        },
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
  PARSE_FILES: {
        require Org::Parser;
        my $parser = Org::Parser->new;

        for my $file (@{ $args{files} }) {
            my $doc;
            if ($file eq '-') {
                binmode STDIN, ":encoding(utf8)";
                $doc = $parser->parse(join "", <>);
            } else {
                local $ENV{PERL_ORG_PARSER_CACHE} = $ENV{PERL_ORG_PARSER_CACHE} // 1;
                $doc = $parser->parse_file($file);
            }
            push @trees, $doc;
        } # for file
    } # PARSe_FILES

    my @entries;
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

        for my $tree (@trees) {
            my @nodes = Data::CSel::csel({
                class_prefixes => ["Org::Element"],
            }, $expr, $tree);
            push @entries, @nodes;
        }
    } # FIND_ENTRIES
    log_trace "Number of matching entries: %d", scalar(@entries);

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

        my ($re_field, $expr_field);
      ENTRY:
        for my $entry (@entries) {

            my @fields;
            if (defined $args{field}) {
                unless (defined $expr_field) {
                    $expr_field = '';
                    $expr_field .= 'ListItem[desc_term.text';
                    if (ref $args{field} eq 'Regexp') {
                        $re_field = $args{field};
                    } else {
                        $re_field = quotemeta($args{field});
                        $re_field = qr/$re_field/;
                    }
                    $expr_field .= " =~ " . Data::Dmp::dmp($re_field) . "]";
                }

                @fields = Data::CSel::csel({
                    class_prefixes => ["Org::Element"],
                }, $expr_field, $entry);

                next ENTRY unless @fields;
            }

            unless ($args{detail} && $args{hide_entry}) {
                unless ($args{hide_category}) {
                    print _highlight(
                        $clrtheme_obj,
                        $re_category,
                        $entry->parent->title->text) . "/";
                }
                print _highlight(
                    $clrtheme_obj,
                    $re_entry,
                    $entry->title->text,
                );
                print "\n";
            }

            if ($args{detail} && !defined($args{field})) {
                print $entry->children_as_string;
            } elsif (@fields) {
                for my $field (@fields) {
                    my $str = _highlight(
                        $clrtheme_obj,
                        $re_field,
                        $field->desc_term->text,
                    ) . " ::" . $field->children_as_string;
                    $str =~ s/^/  /gm;
                    print $str;
                }
            }
        }
    }

    [200];
}
1;
#ABSTRACT:

=head1 SYNOPSIS

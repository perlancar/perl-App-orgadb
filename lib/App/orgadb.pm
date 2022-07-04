package App::orgadb;

use 5.010001;
use strict;
use warnings;
use Log::ger;

use App::orgadb::Common;

# AUTHORITY
# DATE
# DIST
# VERSION

our %SPEC;

$SPEC{':package'} = {
    v => 1.1,
    summary => 'An opinionated Org addressbook tool',
};

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
sub _select_addressbook_entries_single {
    my %args = @_;

    #print "$_ => $args{$_}\n" for sort keys %args;

    my $trees = $args{_trees};
    my $tree_filenames = $args{_tree_filenames};

    my $res = [200, "OK", ""];

    my $formatter;
    if ($args{formatters} && @{ $args{formatters} }) {
        my @filter_names;
        for my $f (@{ $args{formatters} }) {
            if ($f =~ /\A\[/) {
                require JSON::PP;
                $f = JSON::PP::decode_json($f);
            }
            push @filter_names, $f;
        }
        require Data::Sah::Filter;
        $formatter = Data::Sah::Filter::gen_filter(
            filter_names => \@filter_names,
        );
    }

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
            if ($args{num_entries} && @matching_entries > $args{num_entries}) {
                splice @matching_entries, $args{num_entries};
                last FIND_ENTRIES;
            }
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

                if ($args{num_fields} && @matching_fields > $args{num_fields}) {
                    splice @matching_fields, $args{num_fields};
                }

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
            if ($args{detail}) {
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
                    $field_value = $formatter->($field_value) if $formatter;
                    $res->[2] .= $field_value;
                }
            }
        }
    }

    $res;
}

sub _select_addressbook_entries_shell {
    my %args = @_;

    require App::orgadb::Shell;
    my $shell = App::orgadb::Shell->new(
        orgadb_args => \%args,
    );

    $shell->cmdloop;
    [200];
}

$SPEC{select_addressbook_entries} = {
    v => 1.1,
    summary => 'Select Org addressbook entries/fields/subfields',
    args => {
        %App::orgadb::Common::argspecs_common,
        %App::orgadb::Common::argspecs_select,
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

    return [400, "Please specify at least one file"] unless @{ $args{files} || [] };

    my $code_parse_files = sub {
        my @filenames = @_;

        my @trees;
        my @tree_filenames;

        require Org::Parser;
        my $parser = Org::Parser->new;

        for my $filename (@filenames) {
            my $doc;
            if ($filename eq '-') {
                binmode STDIN, ":encoding(utf8)";
                $doc = $parser->parse(join "", <>);
            } else {
                local $ENV{PERL_ORG_PARSER_CACHE} = $ENV{PERL_ORG_PARSER_CACHE} // 1;
                if ($filename =~ /\.gpg\z/) {
                    require IPC::System::Options;
                    my $content;
                    IPC::System::Options::system(
                        {log=>1, capture_stdout=>\$content, die=>1},
                        "gpg", "-d", $filename);
                    $doc = $parser->parse($content);
                } else {
                    $doc = $parser->parse_file($filename);
                }
            }
            push @trees, $doc;
            push @tree_filenames, $filename;
        } # for filename

        return (\@trees, \@tree_filenames);
    };

    if ($args{shell}) {
        _select_addressbook_entries_shell(
            _code_parse_files => $code_parse_files,
            %args,
        );
    } else {
        my ($trees, $tree_filenames) = $code_parse_files->(@{ $args{files} });
        _select_addressbook_entries_single(
            %args,
            _trees => $trees,
            _tree_filenames => $tree_filenames,
        );
    }
}

1;
#ABSTRACT:

=head1 SYNOPSIS

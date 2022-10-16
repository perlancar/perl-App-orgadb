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
    summary => 'An opinionated Org addressbook toolset',
};

sub _highlight {
    my ($clrtheme_obj, $re, $text) = @_;
    return $text unless $clrtheme_obj && $re;

    require ColorThemeUtil::ANSI;
    my $ansi_highlight = ColorThemeUtil::ANSI::item_color_to_ansi($clrtheme_obj->get_item_color('highlight'));
    $text =~ s/($re)/$ansi_highlight$1\e[0m/g;
    $text;
}

# this is like select(), but selects from object trees instead of from an Org
# file.
sub _select_single {
    my %args = @_;

    #print "$_ => $args{$_}\n" for sort keys %args;

    my $trees = $args{_trees};
    my $tree_filenames = $args{_tree_filenames};

    my $res = [200, "OK", ""];
    my @outputted_field_values;

    my @parsed_field_value_formatter_rules;

    my $field_value_formatter_from_args;
  SET_FIELD_VALUE_FORMATTERS_FROM_ARGS:
    {
        last if $args{no_field_value_formatters};
        last unless $args{field_value_formatters} && @{ $args{field_value_formatters} };
        my @filter_names;
        for my $f (@{ $args{field_value_formatters} }) {
            if ($f =~ /\A\[/) {
                require JSON::PP;
                $f = JSON::PP::decode_json($f);
            } else {
                if ($f =~ /(.+)=(.*)/) {
                    my ($modname, $args) = ($1, $2);
                    # normalize / to :: in the module name part
                    $modname =~ s!/!::!g;
                    $f = [$modname, { split /,/, $args }];
                } else {
                    # normalize / to ::
                    $f =~ s!/!::!g;
                }
            }
            push @filter_names, $f;
        }
        require Data::Sah::Filter;
        $field_value_formatter_from_args = Data::Sah::Filter::gen_filter(
            filter_names => \@filter_names,
            return_type => 'str_errmsg+val',
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
                $re_category = qr/$re_category/i;
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
                $re_entry = qr/$re_entry/i;
            }
            $expr .= " =~ " . Data::Dmp::dmp($re_entry) . "]";
        }

        if (defined($args{filter_entries_by_fields}) && @{ $args{filter_entries_by_fields} }) {
            require Regexp::From::String;
            my $expr_field = '';
            for my $field_term (@{ $args{filter_entries_by_fields} }) {
                my ($field_name, $field_value);
                if ($field_term =~ /(.+?)\s*=\s*(.+)/) {
                    $field_name = Regexp::From::String::str_to_re({case_insensitive=>1}, $1);
                    $field_value = Regexp::From::String::str_to_re({case_insensitive=>1}, $2);
                } else {
                    $field_name = Regexp::From::String::str_to_re({case_insensitive=>1}, $field_term);
                }
                #$expr_field .= ($expr_field ? ' > List > ' : 'Headline[level=2] > List > ');
                $expr_field .= ($expr_field ? ' > List > ' : 'List > ');
                $expr_field .= 'ListItem[desc_term.text =~ '.Data::Dmp::dmp($field_name).']';
                if ($field_value) {
                    $expr_field .= '[children_as_string =~ '.Data::Dmp::dmp($field_value).']';
                }
            }
            $expr .= ":has($expr_field)";
        }

        log_trace "CSel expression for selecting entries: <$expr>";

        for my $tree (@$trees) {
            my @nodes = Data::CSel::csel({
                class_prefixes => ["Org::Element"],
            }, $expr, $tree);
            #use Tree::Dump; for (@nodes) { td $_; print "\n\n\n" }
            push @matching_entries, @nodes;
            if ($args{num_entries} && @matching_entries > $args{num_entries}) {
                splice @matching_entries, $args{num_entries};
                last FIND_ENTRIES;
            }
        }
    } # FIND_ENTRIES
    log_trace "Number of matching entries: %d", scalar(@matching_entries);

    #use Tree::Dump; for (@matching_entries) { td $_; print "\n" }
  DISPLAY_ENTRIES: {
        if ($args{count}) {
            return [200, "OK", scalar(@matching_entries)];
        }

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
        my $i = -1;
      ENTRY:
        for my $entry (@matching_entries) {
            $i++;

            my @matching_fields;
            if (defined($args{fields}) && @{ $args{fields} }) {
                unless (defined $expr_field) {
                    $expr_field = '';
                    for my $field_term (@{ $args{fields} }) {
                        $expr_field .= ($expr_field ? ' > List > ' : 'Headline[level=2] > List > ');
                        $expr_field .= 'ListItem[desc_term.text';
                        my $re_field;
                        if (ref $field_term eq 'Regexp') {
                            $re_field = $field_term;
                        } else {
                            $re_field = quotemeta($field_term);
                            $re_field = qr/$re_field/i;
                        }
                        $expr_field .= " =~ " . Data::Dmp::dmp($re_field) . "]";
                        push @re_field, $re_field;
                    }
                    log_trace "CSel expression for selecting fields: <$expr_field>";
                }

                @matching_fields = Data::CSel::csel({
                    class_prefixes => ["Org::Element"],
                }, $expr_field, $entry);
                log_trace "Number of matching fields for entry #$i: %d", scalar(@matching_fields);

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
                    my $field_name0 = $field->desc_term->text;
                    unless ($args{hide_field_name}) {
                        my $field_name = '';
                        $field_name = _highlight(
                            $clrtheme_obj,
                            $re_field,
                            $field->bullet . ' ' . $field_name0,
                        ) . " ::";
                        unless ($args{clipboard} && $args{clipboard} eq 'only') {
                            $res->[2] .= $field_name;
                        }
                    }

                    my $field_value_formatter_from_rules;
                  SET_FIELD_VALUE_FORMATTERS_FROM_RULES:
                    {
                        last if $args{no_field_value_formatters};
                        last if $field_value_formatter_from_args;
                        last unless $args{field_value_formatter_rules} && @{ $args{field_value_formatter_rules} };

                        my $field_value_formatters_from_rules = [];
                        unless (@parsed_field_value_formatter_rules) {
                            my $i = -1;
                            for my $r0 (@{ $args{field_value_formatter_rules} }) {
                                $i++;
                                my $r;
                                if (!ref($r0) && $r0 =~ /\A\{/) {
                                    require JSON::PP;
                                    $r = JSON::PP::decode_json($r0);
                                } else {
                                    $r = {%$r0};
                                }

                                # precompile regexes
                                require Regexp::From::String;
                                if (defined $r->{field_name_matches}) {
                                    $r->{field_name_matches} = Regexp::From::String::str_to_re({case_insensitive=>1}, $r->{field_name_matches});
                                }

                                if ($r->{formatters} && @{ $r->{formatters} }) {
                                    my @filter_names;
                                    for my $f (@{ $r->{formatters} }) {
                                        if ($f =~ /\A\[/) {
                                            require JSON::PP;
                                            $f = JSON::PP::decode_json($f);
                                        } else {
                                            if ($f =~ /(.+)=(.*)/) {
                                                my ($modname, $args) = ($1, $2);
                                                # normalize / to :: in the module name part
                                                $modname =~ s!/!::!g;
                                                $f = [$modname, { split /,/, $args }];
                                            } else {
                                                # normalize / to ::
                                                $f =~ s!/!::!g;
                                            }
                                        }
                                        push @filter_names, $f;
                                    }
                                    require Data::Sah::Filter;
                                    $r->{formatter} = Data::Sah::Filter::gen_filter(
                                        filter_names => \@filter_names,
                                        return_type => 'str_errmsg+val',
                                    );
                                } else {
                                    die "Field value formatting rules [$i] does not have non-empty formatters: %s", $r;
                                }
                                push @parsed_field_value_formatter_rules, $r;
                            }
                            #log_error "parsed_field_value_formatter_rules=%s", \@parsed_field_value_formatter_rules;
                        } # set @parsed_field_value_formatter_rules

                        # do the filtering
                        my $i = -1;
                      RULE:
                        for my $r (@parsed_field_value_formatter_rules) {
                            $i++;
                            my $matches = 1;
                            if (defined $r->{field_name_matches}) {
                                $field_name0 =~ $r->{field_name_matches} or do {
                                    $matches = 0;
                                    log_trace "Skipping field_value_formatter_rules[%d]: field_name_matches %s doesn't match %s", $i, $r->{field_name_matches}, $field_name0;
                                    next RULE;
                                };
                            }
                            if (defined $r->{hide_field_name}) {
                                if ($args{hide_field_name} xor $r->{hide_field_name}) {
                                    $matches = 0;
                                    log_trace "Skipping field_value_formatter_rules[%d]: hide_field_name condition (%s) doesn't match actual hide_field_name option (%s)", $i, ($r->{hide_field_name} ? 'true':'false'), ($args{hide_field_name} ? 'true':'false');
                                    next RULE;
                                }
                            }
                            log_trace "Adding field value formatters from field_value_formatter_rules[%d] (%s) for field name %s", $i, $r->{formatters}, $field_name0;
                            push @$field_value_formatters_from_rules, $r->{formatter};
                        }
                        # combine default formatters
                        last unless @$field_value_formatters_from_rules;
                        if (@$field_value_formatters_from_rules > 1) {
                            $field_value_formatter_from_rules = sub {
                                my $val = shift;
                                my $res;
                                for my $i (0 .. $#{$field_value_formatters_from_rules}) {
                                    $res = $field_value_formatters_from_rules->[$i]->($val);
                                    return $res if $res->[0];
                                    $val = $res->[1];
                                }
                                $res;
                            };
                        } else {
                            $field_value_formatter_from_rules = $field_value_formatters_from_rules->[0];
                        }
                    } # SET_FIELD_VALUE_FORMATTERS_FROM_RULES

                    my $field_value0 = $field->children_as_string;
                    my ($prefix, $field_value, $suffix) = $field_value0 =~ /\A(\s+)(.*?)(\s*)\z/s;
                    if ($field_value_formatter_from_args || $field_value_formatter_from_rules) {
                        my ($ferr, $fres) = @{ ($field_value_formatter_from_args || $field_value_formatter_from_rules)->($field_value) };
                        if ($ferr) {
                            log_warn "Field value formatting error: field value=%s, errmsg=%s", $field_value, $ferr;
                            $field_value = "$field_value # CAN'T FORMAT: $ferr";
                        } else {
                            $field_value = $fres;
                        }
                    }
                    unless ($args{clipboard} && $args{clipboard} eq 'only') {
                        $res->[2] .= ($args{hide_field_name} ? "" : $prefix) . $field_value . $suffix;
                    }
                    push @outputted_field_values, $field_value;
                }
            }
        }
    }

  COPY_TO_CLIPBOARD: {
        last unless $args{clipboard};
        last unless @outputted_field_values;
        require Clipboard::Any;
        log_info "Copying matching field values to clipboard ...";
        my $res = Clipboard::Any::add_clipboard_content(content => join "\n", @outputted_field_values);
        if ($res->[0] != 200) {
            log_warn "Cannot copy to clipboard: $res->[0] - $res->[1]";
            last;
        }
    }

    $res;
}

sub _select_shell {
    my %args = @_;

    require App::orgadb::Select::Shell;
    my $shell = App::orgadb::Select::Shell->new(
        main_args => \%args,
    );

    $shell->cmdloop;
    [200];
}

$SPEC{select} = {
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
sub select {
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
        _select_shell(
            _code_parse_files => $code_parse_files,
            %args,
        );
    } else {
        my ($trees, $tree_filenames) = $code_parse_files->(@{ $args{files} });
        _select_single(
            %args,
            _trees => $trees,
            _tree_filenames => $tree_filenames,
        );
    }
}

1;
#ABSTRACT:

=head1 SYNOPSIS

=head1 DESCRIPTION

This distribution includes the following CLI's:

# INSERT_EXECS_LIST

=cut

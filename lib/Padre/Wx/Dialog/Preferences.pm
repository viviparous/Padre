package Padre::Wx::Dialog::Preferences;

use 5.008;
use strict;
use warnings;
use Padre::Locale               ();
use Padre::Document             ();
use Padre::Wx                   ();
use Padre::Wx::Role::Config     ();
use Padre::Wx::FBP::Preferences ();
use Padre::Logger;

our $VERSION = '0.85';
our @ISA     = qw{
	Padre::Wx::Role::Config
	Padre::Wx::FBP::Preferences
};





#####################################################################
# Class Methods

# One-shot creation, display and execution.
# Does return the object, but we don't expect anyone to use it.
sub run {
	my $class = shift;
	my $main  = shift;
	my $self  = $class->new($main);

	# Load preferences from configuration
	my $config = $main->config;
	$self->config_load($config);

	# Show the dialog
	$self->Fit;
	$self->CentreOnParent;
	if ( $self->ShowModal == Wx::wxID_CANCEL ) {
		return;
	}

	# Save back to configuration
	$self->config_save($config);

	# Clean up
	$self->Destroy;
	return 1;
}





#####################################################################
# Constructor and Accessors

sub new {
	TRACE( $_[0] ) if DEBUG;
	my $self = shift->SUPER::new(@_);

	# Set the content of the editor preview
	$self->preview->{Document} = Padre::Document->new(
		mimetype => 'application/x-perl',
	);
	$self->preview->{Document}->set_editor( $self->preview );
	$self->preview->SetText(
		join '', map {"$_\n"}
			"#!/usr/bin/perl",
		"",
		"use strict;",
		"",
		"main();",
		"",
		"exit 0;",
		"",
		"sub main {",
		"\t# some senseles comment",
		"\tmy \$x = \$_[0] ? \$_[0] : 5;",
		"\tif ( \$x > 5 ) {",
		"\t\treturn 1;",
		"\t} else {",
		"\t\treturn 0;",
		"\t}",
		"}",
		"",
		"__END__",
	);

	# Build the list of configuration dialog elements.
	# We assume all public dialog elements will match a wx widget with
	# a public method returning it.
	$self->{names} = [ grep { $self->can($_) } $self->config->settings ];

	return $self;
}

sub names {
	return @{ $_[0]->{names} };
}





#####################################################################
# Padre::Wx::Role::Config Methods

sub config_load {
	TRACE( $_[0] ) if DEBUG;
	my $self   = shift;
	my $config = shift;

	# We assume all public dialog elements will match a wx widget with
	# a public method returning it.
	$self->SUPER::config_load( $config, $self->names );

	# Sync the editor preview to the current config
	$self->preview->set_preferences;

	### HACK
	# Backup the editor style
	$self->{original_style} = $config->editor_style;

	return 1;
}

# Customised with an extra hack
sub config_diff {
	my $self   = shift;
	my $config = shift;
	my %diff   = ();

	# Iterate over the configuration entries and apply the
	# configuration state to the dialog.
	foreach my $name ( $config->settings ) {
		next unless $self->can($name);

		# Get the Wx element for this option
		my $setting = $config->meta($name);
		my $old     = $config->$name();
		my $ctrl    = $self->$name();

		### HACK
		# Get the "old" value from the backed up copy of the style
		if ( $name eq 'editor_style' ) {
			$old = $self->{original_style};
		}

		# Don't capture options that are not shown,
		# as this may result in falsely clearing them.
		next unless $ctrl->IsEnabled;

		# Extract the value from the control
		my $value = undef;
		if ( $ctrl->isa('Wx::CheckBox') ) {
			$value = $ctrl->GetValue ? 1 : 0;

		} elsif ( $ctrl->isa('Wx::TextCtrl') ) {
			$value = $ctrl->GetValue;

		} elsif ( $ctrl->isa('Wx::SpinCtrl') ) {
			$value = $ctrl->GetValue;

		} elsif ( $ctrl->isa('Wx::ColourPickerCtrl') ) {
			$value = $ctrl->GetColour->GetAsString(Wx::wxC2S_HTML_SYNTAX);
			$value =~ s/^#// if defined $value;

		} elsif ( $ctrl->isa('Wx::FontPickerCtrl') ) {
			$value = $ctrl->GetSelectedFont->GetNativeFontInfoUserDesc;

		} elsif ( $ctrl->isa('Wx::Choice') ) {
			my $options = $setting->options;
			if ($options) {
				my @k = sort keys %$options;
				my $i = $ctrl->GetSelection;
				$value = $k[$i];
			}
		} else {

			# To be completed
		}

		# Skip if null
		next unless defined $value;
		next if $value eq $old;
		$diff{$name} = $value;
	}

	return unless %diff;
	return \%diff;
}





######################################################################
# Event Handlers

sub cancel {
	TRACE( $_[0] ) if DEBUG;
	my $self = shift;

	# Apply the original style
	my $style = delete $self->{original_style};
	$self->main->action("view.style.$style");

	# Cancel the preferences dialog in Wx
	$self->EndModal(Wx::wxID_CANCEL);

	return;
}

sub advanced {
	TRACE( $_[0] ) if DEBUG;
	my $self = shift;

	# Cancel the preferences dialog since it is not needed
	$self->cancel;

	# Show the advanced settings dialog instead
	require Padre::Wx::Dialog::Advanced;
	my $advanced = Padre::Wx::Dialog::Advanced->new( $self->main );
	my $ret      = $advanced->show;

	return;
}

sub guess {
	my $self     = shift;
	my $document = $self->current->document or return;
	my $indent   = $document->guess_indentation_style;

	$self->editor_indent_tab->SetValue( $indent->{use_tabs} );
	$self->editor_indent_tab_width->SetValue( $indent->{tabwidth} );
	$self->editor_indent_width->SetValue( $indent->{indentwidth} );

	return;
}

# We do this the long-hand way for now, as we don't have a suitable
# method for generating proper logical style objects.
sub preview_refresh {
	TRACE( $_[0] ) if DEBUG;
	my $self    = shift;
	my $config  = $self->config;
	my $preview = $self->preview;

	# Set the colour of the current line (if visible)
	if ( $config->editor_currentline ) {
		$preview->SetCaretLineBackground( $self->editor_currentline_color->GetColour );
	}

	# Set the font for the editor
	my $font = $self->editor_font->GetSelectedFont;
	$preview->SetFont($font);
	$preview->StyleSetFont( Wx::wxSTC_STYLE_DEFAULT, $font );

	# Set the right margin if applicable
	if ( $self->editor_right_margin_enable->GetValue ) {
		$preview->SetEdgeColumn( $self->editor_right_margin_column );
		$preview->SetEdgeMode(Wx::wxSTC_EDGE_LINE);
	} else {
		$preview->SetEdgeMode(Wx::wxSTC_EDGE_NONE);
	}

	# Apply the style (but only if we can do so safely)
	if ( $self->{original_style} ) {
		my $style = $self->choice('editor_style');

		# Removed for RELEAES_TESTING=1 pass
		#Padre::Current->main->action("view.style.$style");
		$self->current->main->action("view.style.$style");
		$preview->set_preferences;
	}

	return;
}





######################################################################
# Support Methods

# Convenience method to get the current value for a single named choice
sub choice {
	my $self    = shift;
	my $name    = shift;
	my $ctrl    = $self->$name() or return;
	my $setting = $self->config->meta($name) or return;
	my $options = $setting->options or return;
	my @results = sort keys %$options;
	return $results[ $ctrl->GetSelection ];
}

1;

# Copyright 2008-2011 The Padre development team as listed in Padre.pm.
# LICENSE
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl 5 itself.


use MooseX::Declare;

# TODO do something for the distinguished client module, also implement the
# role-based broadcast mechanism
#
# for broadcast the kernel needs to consider itself as a module... this is
# for configuration changes, and also for receiving module_req_changed

class Soric3::Kernel does Soric3::Meta::Alertable {
    has _config_delegate => (
        isa => 'Soric3::ConfigDelegate',
        is  => 'ro',
        required => 1,
        handles => { set_config => 'set',
                     get_config => 'get' },
    );

    method BUILDARGS ($class: @args) {
        die "You must pass 1 or an even number of arguments"
            unless @args == 1 || (@args % 2) == 0;

        if (@args == 1) {
            return {_config_delegate => $args[0]};
        } else {
            return {_config_delegate => Soric3::HashConfigDelegate->new(@args)};
        }
    }

    has _modules => (
        isa     => 'HashRef[Soric3::Module]',
        is      => 'bare',
        default => sub { {} },
        handles => { loaded_modules => 'keys',
                     module_loaded  => 'exists',
                     _bind_module   => 'set',
                     module         => 'get',
                     _unload_module => 'delete' },
    );

    # Do a preorder traversal of the module dependancy tree, instantiating and
    # binding all new modules, and removing unused ones.  This is done from an
    # idle handler to preserve the property that configuration changes are
    # nonfinal before returning to the main loop.
    method _load_module(HashRef $used, Str $name where { $_ =~ /^[a-z]+$/) {
        return if $used->{$name};

        my $class_name = "Soric3::Module::" . uc($name);
        Class::MOP::load_class($class_name);

        $used->{$name} = 1;

        $self->_load_module($used, $_) for $name->requires;

        $self->_bind_module($name, $class_name->new(kernel => $self));
    }

    method _react() {
        my %used;

        $self->_load_module(\%used, $_)
            for ($self->_config_delegate->keys());

        for my $mod ($self->loaded_modules) {
            next if $used{$mod};

            $self->_unload_module($mod);
        }
    }

    after set_config => sub {
        my ($self, @path) = @_;

        for my $mod (@path ? $path[0] : $self->loaded_modules) {
            next unless $self->module_loaded($mod);
            $self->module($mod)->config_changed(@path);
        }

        $self->_alert;
    };

    method BUILD {
        $self->_alert;
    }
}

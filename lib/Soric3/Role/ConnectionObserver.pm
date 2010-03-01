use MooseX::Declare;

role Soric3::Role::ConnectionObserver {
    requires "connection_status_changed";
}

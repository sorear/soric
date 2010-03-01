use MooseX::Declare;

role Soric3::Role::SendQueueObserver {
    requires "sends_changed";
}

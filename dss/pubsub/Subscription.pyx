cdef class Subscription:
    def __init__(self, channel, subscriber, include_subchannels=0, async=1, thread_id=0):
        self.is_active = True
        self.timestamp = time_of_day()
        self.channel = channel
        self.subscriber = subscriber
        self.include_subchannels = include_subchannels
        self.async = async
        self.thread_id = thread_id
        self.message_count = 0

    def cancel(self):
        self.is_active = False
        self.channel.unsubscribe(self)

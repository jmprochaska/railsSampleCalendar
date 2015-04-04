class Event < ActiveRecord::Base
  has_many :registrations
  has_many :guests, through: :registrations
  has_many :registrations

  has_attached_file :image, styles: {small: "150x100", medium: "300x200", large: "450,300" }, :url => "/assets/:id/:style/:basename.:extension", :path => "public/assets/:id/:style/:basename.:extension", :default_url => "/assets/missing.png"

  #validates_attachment_presence :image
  #validates_attachment_size :image, :less_than => 5.megabytes
  #validates_attachment_content_type :image, :content_type => ['image/jpeg', 'image/png', 'image/jpg']

  do_not_validate_attachment_file_type :image

  # scope :between, lambda {|start_time, end_time|
  #   {:conditions => ["? < start < ?", Event.format_date(start_time), Event.format_date(end_time)] }
  # }

  def as_json(options = {})
  {
    :id => self.id,
    :title => self.name,
    :start => start.iso8601,
    :url => Rails.application.routes.url_helpers.event_path(id)
  }
  end

  # def self.scoped(options=nil)
  #   options ? where(nil).apply_finder_options(options, true) : where(nil)
  # end

  def self.check_if_fields_valid(arg1)
    result = {}
    result[:message] = []
    result[:value] = true
    arg1.each do |k, v|
      if v == nil || v == ''
        result[:value] = false
        result[:message].append k.to_s
      end
    end
    result
  end

  def is_new?
    Event.find_by_meetup_id(meetup_id).nil?
  end

  def is_updated?(latest_update)
    updated < latest_update
  end

  def count_event_participants
    regis = self.registrations
    sum = 0
    regis.each do |reg|
      sum += 1 + reg.invited_guests
    end
    sum
  end

  def generate_participants_message
    "The total number of participants, including invited guests, so far is:" +
      " #{self.count_event_participants}"
  end

  def self.get_remote_events(options={})
    # Here we can pass the token to the API call if needed.
    # We can also pass any options for the query
    # If so put them in the options hash, and pass it to the constructor
    #options = {access_token: token}
    meetup = Meetup.new(options)

    candidate_events = []
    meetup_events = meetup.pull_events
    if meetup_events
      meetup_events.each do |event|
        return nil unless true   # ANY VALIDATION???? Check meetup.rb for details
        candidate_events << Event.new(event)
      end
    end

    candidate_events
  end


  def self.make_events_local(events)
    if events
      events_bin = []
      events.each do |event|
        stored_event = Event.find_by_meetup_id(event[:meetup_id])
        if stored_event.nil?
          event.save!
        elsif stored_event.is_updated?(event[:updated])
          stored_event.update_attributes!(event.attributes)
        else # already stored and unchanged since
          next
        end

        events_bin << event
      end

      events_bin
    end
  end


  # Gets meetup rsvps corresponding to a given event id
  # Non-nil returned output is always valid
  def get_remote_rsvps
    # Could pass arguments to constructor to refine search
    meetup = Meetup.new
    meetup.pull_rsvps(meetup_id)
  end


  def merge_meetup_rsvps
    rsvps = get_remote_rsvps

    if rsvps
      new_guest_names = []
      rsvps.each do |rsvp|

        guest = Guest::find_guest_by_meetup_rsvp(rsvp) || Guest::create_guest_by_meetup_rsvp(rsvp)

        registration = Registration.find_by({event_id: id, guest_id: guest.id})
        if registration.nil?
          Registration.create!(event_id: id, guest_id: guest.id,
                               invited_guests: rsvp[:invited_guests],
                               updated: rsvp[:updated])
        elsif registration.is_updated?(rsvp[:updated])
          registration.update_attributes!(invited_guests: rsvp[:invited_guests],
                                          updated: rsvp[:updated])
        else # neither new nor updated
          next
        end

        new_guest_names << guest.first_name + (' ' if guest.last_name) + guest.last_name
      end

      new_guest_names
    end
  end

  def format_date
    start.strftime("%m/%d/%Y at %I:%M%p")
  end
end

class Event < ActiveRecord::Base
  has_many :registrations
  has_many :guests, through: :registrations
  has_many :registrations

  has_attached_file :image, styles: {original: "300x200"}, :url => "/assets/:id/:style/:basename.:extension",
                    :path => "public/assets/:id/:style/:basename.:extension", :default_url => "/assets/missing.png"

  do_not_validate_attachment_file_type :image
  #validates_attachment_presence :image
  #validates_attachment_size :image, :less_than => 5.megabytes
  #validates_attachment_content_type :image, :content_type => ['image/jpeg', 'image/png', 'image/jpg']

  DEFAULT_DATE_FORMAT = '%b %e, %Y at %l:%M%P'
  DEFAULT_TIME_FORMAT = '%l:%M%P'

  def as_json(options={})
    {
      :id => self.id,
      :title => self.name,
      :start => self.start.iso8601,
      :end => (stop = self.end) ? stop.iso8601 : nil,
      :location => {event_st_number: st_number, event_st_name: st_name, event_city: city,
                    event_state: state, event_zip: zip, event_country: country},
      :description => self.description,
      :url => Rails.application.routes.url_helpers.event_path(id)
    }
  end

  def is_new?
    self.class.find_by_meetup_id(meetup_id).nil?
  end

  def needs_updating?(latest_update)
    updated < latest_update
  end

  def self.get_remote_events(options={})
    meetup_events = Meetup.new.pull_events(options)
    if meetup_events.respond_to?(:each)
      meetup_events.each_with_object([]) {|event, candidate_events| candidate_events << Event.new(event)}
    end
  end

  def self.process_remote_events(events)
    return if events.blank?
    events.each {|event| Event.process_event(event)}
  end

  def self.process_event(event)
    stored_event = Event.find_by_meetup_id(event[:meetup_id])
    return event.save if stored_event.nil?
    stored_event.apply_update(event) if stored_event.needs_updating?(event[:updated])
  end

  def self.remove_remotely_deleted_events(remote_events)
    return if remote_events.nil?
    remotely_deleted_ids = Event.get_remotely_deleted_ids(remote_events)
    remotely_deleted_ids.each {|id| Event.find_by_meetup_id(id).destroy}
  end

  def self.get_remotely_deleted_ids(remote_events)
    target_events = Event.where("start >= '#{DateTime.now - 1}'")
    local_event_ids = target_events.inject([]) {|array, event| array << event.meetup_id}
    remote_event_ids = remote_events.inject([]) {|array, event| array << event.meetup_id}
    local_event_ids - remote_event_ids
  end

  def self.get_upcoming_events
    Event.get_remote_events({status: 'upcoming'})
  end

  def self.get_past_events(from=nil, to=nil)
    Event.get_remote_events({status: 'past'}.merge Event.date_range(from, to))
  end

  def self.get_upcoming_third_party_events
    ids = Event.get_stored_third_party_ids
    if ids.size > 0
      options = {event_id: ids.join(',')}
      events = Event.get_remote_events({status: 'upcoming'}.merge options)
      return events if events
    end
    []
  end

  def self.get_past_third_party_events(from=nil, to=nil)
    ids = Event.get_stored_third_party_ids
    if ids.size > 0
      options = {event_id: ids.join(',')}
      range = Event.date_range(from, to)
      events = Event.get_remote_events(({status: 'past'}.merge options).merge range)
      return events if events
    end
    []
  end

  def self.date_range(from=nil, to=nil)
    (from || to) ? {time: "#{from},#{to}"} : {}
  end

  def self.store_third_party_events(ids)
    options = ids.respond_to?(:join) ? {event_id: ids.join(',')} : {}
    Event.process_remote_events(Event.get_remote_events(options))
  end

  def self.initialize_calendar_db
    upcoming_events = Event.get_upcoming_events
    past_events = Event.get_past_events
    remote_events = upcoming_events && past_events ? upcoming_events + past_events : nil
    process_remote_events(remote_events)
  end

  def self.synchronize_past_events
    group_events = Event.get_past_events('-1d', '')
    third_party_events = Event.get_past_third_party_events('-1d', '')
    remote_events = group_events && third_party_events ? group_events + third_party_events : nil
    process_remote_events(remote_events)
  end

  def self.synchronize_upcoming_events
    group_events = Event.get_upcoming_events
    third_party_events = Event.get_upcoming_third_party_events
    remote_events = group_events && third_party_events ? group_events + third_party_events : nil
    Event.remove_remotely_deleted_events(remote_events)
    process_remote_events(remote_events)
  end

  def self.get_default_group_name
    Meetup::GROUP_NAME
  end

  def self.get_stored_third_party_ids
    Event.all.each_with_object([]) {|event, ids| ids << event.meetup_id if event.is_third_party?}
  end

  def is_third_party?
    default_group_name = Event.get_default_group_name
    group_name = organization
    group_name && group_name != default_group_name
  end

  def apply_update(new_event)
    new_pairs = new_event.attributes
    modified_pairs = new_pairs.select {|key, value| value && value != self[key]}
    update_attributes(modified_pairs)
  end

  def get_remote_rsvps
    Meetup.new.pull_rsvps(event_id: meetup_id)
  end

  def merge_meetup_rsvps
    rsvps = get_remote_rsvps
    return if rsvps.blank?
    rsvps.each do |rsvp|
      guest = Guest.find_by_meetup_rsvp(rsvp) || Guest.create_by_meetup_rsvp(rsvp)
      process_rsvp(rsvp, guest.id)
    end
  end


  def process_rsvp(rsvp, guest_id)
    registration = Registration.find_by({event_id: id, guest_id: guest_id})
    guests = rsvp[:invited_guests]
    updated = rsvp[:updated]
    return  Registration.create!(event_id: id, guest_id: guest_id, invited_guests: guests, updated: updated) if registration.nil?
    registration.update_attributes!(invited_guests: guests, updated: updated) if registration.needs_updating?(updated)
  end

  def self.get_requested_ids(data)
    data.keys.select {|key| key =~ /^event.+$/} if data.respond_to? :keys
  end

  def self.cleanup_ids(ids)
    clean_ids = []
    ids.each {|id| clean_ids << id.gsub("event", "")} if ids.respond_to? :each
    clean_ids
  end

  def self.get_event_ids(args)
    Event.cleanup_ids(Event.get_requested_ids(args))
  end

  def updated_fields
    attributes.compact
  end

  def location
    location = []
    street = "#{st_number} #{st_name}"
    append_to_list(location, street)
    append_to_list(location, city)

    state_zip_list = []
    append_to_list(state_zip_list, state)
    append_to_list(state_zip_list, zip)
    state_zip = state_zip_list.join(' ').strip

    append_to_list(location, state_zip)
    append_to_list(location, country)
    location.join(', ')
  end

  # Appends field to lst if field is neither nil nor whitespace
  def append_to_list(lst, field)
    if (field != nil) and (field.strip != '')
      lst << field
    end
  end

  def update_meetup_fields(event)
    keys = [:meetup_id, :updated, :url, :status]
    keys.each {|key| self[key] = event[key]}
  end

  def format_start_date
    Event.format_date(start)
  end

  def format_end_date
    Event.format_date(self.end)
  end

  def self.format_date(date)
    date.strftime(DEFAULT_DATE_FORMAT) if date
  end

  def at_least_1_day_long?
    (self.end - self.start) >= 1.day
  end

  def pick_end_time_type
    return format_end_date if at_least_1_day_long?
    self.end.strftime(DEFAULT_TIME_FORMAT)
  end

  def format_time
    start_time = format_start_date
    end_time = pick_end_time_type
    "#{start_time} to #{end_time}"
  end

end

@javascript
Feature: See who RSVPed for event

  As a user
  So that I can predict who's attending the event
  I want to be able to view who has RSVPed to the event

Background:
  Given the following events exist:
    | name             | organization       | description                               | venue_name                 | address_1      | city     | zip   | start                | end                  | how_to_find_us     | meetup_id |
    | Nature Walk      | Nature in the City | A walk through the city                   | The Old Town Hall          | 145 Jackson st | Glendale | 90210 | March 19 2015, 16:30 | March 19 2015, 20:30 | First door on left | 342343432 |
    | Green Bean Mixer | Green Carrots      | If you like beans you'll like this event! | San Francisco City Library | 45 Seneca st   | Phoenix  | 91210 | April 20 2015, 8:30  | April 21 2015, 8:30  | Second door on left| 343333333 |

  And the following guests exist:
  | first_name | last_name | phone          | email            | address            | is_anon |
  | John       | Smith     | (816) 567-8521 | jsmith@site.com  | 12 Washington Blvd | false   |
  | Jacob      | Harrison  | (932) 123-4567 | jharry@gmail.com | 10 Whatever St     | true    |
  | Adam       | Johnson   | (123) 987-4321 | ajohns@yahoo.com | 38 Smithsonian Ave | true    |
  | Mary       | Jackson   | (789) 425-8967 | mjacks@msn.com   | 98 White Horse Ave | true    |
  | Max        | Leroy     | (723) 123-8900 | maxler@aol.com   | 69 Feeling St      | false   |

  And the following registrations exist:
  | event_id | guest_id |
  | 1        | 1        |
  | 1        | 2        |
  | 1        | 3        |
  | 2        | 1        |
  | 2        | 2        |
  | 2        | 4        |
  | 2        | 5        |

  And I am on the calendar page
  And the month is March 2015

Scenario: Any user can see the first names of non-anonymous event attendees
  When I click on "Nature Walk" in the calendar
  Then the panel should list the attendees of "Nature Walk" alphabetically by first name
  But it should not list anonymous attendees of "Nature Walk"

Scenario: Admin can see the first names of non-anonymous event attendees
  When I click on "Nature Walk" in the calendar
  Then the panel should list the attendees of "Nature Walk" alphabetically by first name
  And I should see all the information about attendees of "Nature Walk"
# Time units on Integer, so a duration names its unit at the value:
# `15.minutes` instead of `15 * 60`.
#
# This is the part of ActiveSupport that the collector uses, rebuilt in a few
# lines. ActiveSupport itself would add 13 gems and about 12 MB to the image
# for this.
#
# Every method returns a number of seconds as an Integer. The result can be
# added to a Time, and it can be compared to another number of seconds.
class Integer
  def seconds = self

  def minutes = self * 60

  def hours = self * 60 * 60

  def days = self * 24 * 60 * 60

  alias second seconds
  alias minute minutes
  alias hour hours
  alias day days
end

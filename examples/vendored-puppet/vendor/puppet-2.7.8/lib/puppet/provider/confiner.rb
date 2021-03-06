require 'puppet/provider/confine_collection'

module Puppet::Provider::Confiner
  def confine(hash)
    confine_collection.confine(hash)
  end

  def confine_collection
    @confine_collection ||= Puppet::Provider::ConfineCollection.new(self.to_s)
  end

  # Check whether this implementation is suitable for our platform.
  def suitable?(short = true)
    return(short ? confine_collection.valid? : confine_collection.summary)
  end
end

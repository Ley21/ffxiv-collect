# == Schema Information
#
# Table name: characters
#
#  id                 :bigint(8)        not null, primary key
#  name               :string(255)      not null
#  server             :string(255)      not null
#  portrait           :string(255)      not null
#  avatar             :string(255)      not null
#  last_parsed        :datetime         not null
#  verified_user_id   :integer
#  achievements_count :integer          default(0)
#  mounts_count       :integer          default(0)
#  minions_count      :integer          default(0)
#  orchestrions_count :integer          default(0)
#  emotes_count       :integer          default(0)
#  bardings_count     :integer          default(0)
#  hairstyles_count   :integer          default(0)
#  armoires_count     :integer          default(0)
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#

class Character < ApplicationRecord
  after_destroy :clear_user_characters

  %i(achievements mounts minions orchestrions emotes bardings hairstyles armoires).each do |model|
    has_many "character_#{model}".to_sym, dependent: :delete_all
    has_many model, through: "character_#{model}".to_sym
  end

  def refresh
    XIVAPI_CLIENT.character_update(id: self.id)
    Character.fetch(self.id, true)
  end

  def self.sync(ids)
    ids.each { |id| Character.fetch(id, true) }
  end

  def self.fetch(id, skip_cache = false)
    character = Character.find_by(id: id)
    if !skip_cache && character.present?
      return character
    end

    result = XIVAPI_CLIENT.character(id: id, all_data: true, poll: true)
    data = result.character.to_h.slice(:id, :name, :server, :portrait, :avatar)
    data[:last_parsed] = Time.at(result.character.parse_date)

    if character.present?
      character.update(data)
    else
      character = Character.create!(data)
    end

    Character.bulk_insert(data[:id], CharacterAchievement, :achievement,
                          (result.achievements&.list&.map(&:id) || []) - character.achievement_ids)
    Character.bulk_insert(data[:id], CharacterMount, :mount, result.character.mounts - character.mount_ids)
    Character.bulk_insert(data[:id], CharacterMinion, :minion, result.character.minions - character.minion_ids)
    Character.find(id)
  end

  def self.search(server, name)
    XIVAPI_CLIENT.character_search(server: server, name: name).to_a
  end

  def self.servers
    %w(Adamantoise Aegis Alexander Anima Asura Atomos Bahamut Balmung Behemoth Belias Brynhildr Cactuar Carbuncle
    Cerberus Chocobo Coeurl Diabolos Durandal Excalibur Exodus Faerie Famfrit Fenrir Garuda Gilgamesh Goblin Gungnir
    Hades Hyperion Ifrit Ixion Jenova Kujata Lamia Leviathan Lich Louisoix Malboro Mandragora Masamune Mateus Midgardsormr
    Moogle Odin Omega Pandaemonium Phoenix Ragnarok Ramuh Ridill Sargatanas Shinryu Shiva Siren Tiamat Titan Tonberry
    Typhon Ultima Ultros Unicorn Valefor Yojimbo Zalera Zeromus Zodiark).freeze
  end

  private
  def self.bulk_insert(character_id, model, model_name, ids)
    return unless ids.present?
    date = Time.now.to_formatted_s(:db)
    values = ids.map { |id| "(#{character_id}, #{id}, '#{date}', '#{date}')" }
    model.connection.execute("INSERT INTO #{model.table_name}(character_id, #{model_name}_id, created_at, updated_at)" \
                             " values #{values.join(',')}")
    Character.reset_counters(character_id, "#{model_name}s_count")
  end

  def clear_user_characters
    User.where(character_id: self.id).update_all(character_id: nil)
  end
end
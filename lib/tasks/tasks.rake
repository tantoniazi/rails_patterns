# lib/tasks/cards.rake
namespace :cards do
  desc "Migrar cards sem fase para a fase inicial do pipe"
  task migrate_orphans: :environment do
    puts "[#{Time.current}] Iniciando migração de cards orfãos..."

    orphans = Card.unscoped.where(phase_id: nil)
    total   = orphans.count
    puts "Encontrados #{total} cards orfãos."

    success = 0
    failure = 0

    orphans.find_each do |card|
      default_phase = card.pipe&.phases&.first
      if default_phase
        card.update_column(:phase_id, default_phase.id)
        success += 1
        print "."
      else
        failure += 1
        Rails.logger.warn("Card #{card.id} sem pipe válido")
        print "F"
      end
    end

    puts "\nConcluído! Sucesso: #{success}, Falha: #{failure}"
  end

  desc "Expirar cards vencidos (executar via cron diário)"
  task expire_overdue: :environment do
    puts "[#{Time.current}] Expirando cards vencidos..."
    count = 0

    Card.overdue.find_each do |card|
      Cards::ExpireService.call(card:)
      count += 1
    end

    puts "#{count} cards expirados."
  end

  desc "Reprocessar eventos Kafka com falha (dry_run=true para simular)"
  task :reprocess_failed_events, [:dry_run] => :environment do |_, args|
    dry_run = args[:dry_run] == "true"
    puts dry_run ? "[DRY RUN] Simulando..." : "Reprocessando eventos..."

    FailedKafkaEvent.pending.find_each do |event|
      puts "Event: #{event.id} - #{event.event_type}"
      event.reprocess! unless dry_run
    end
  end
end

# lib/tasks/db.rake
namespace :db do
  desc "Verificar integridade referencial do banco"
  task integrity_check: :environment do
    puts "Verificando integridade referencial..."

    orphan_cards   = Card.unscoped.where.not(phase_id: Phase.select(:id)).count
    orphan_phases  = Phase.unscoped.where.not(pipe_id: Pipe.select(:id)).count

    puts "Cards com phase inválida: #{orphan_cards}"
    puts "Phases com pipe inválido: #{orphan_phases}"

    if orphan_cards > 0 || orphan_phases > 0
      puts "ATENÇÃO: Problemas de integridade encontrados!"
      exit 1
    else
      puts "OK! Banco íntegro."
    end
  end
end

# lib/tasks/kafka.rake
namespace :kafka do
  desc "Criar topics necessários"
  task create_topics: :environment do
    topics = %w[card_events automation_triggers webhook_deliveries]

    topics.each do |topic|
      puts "Criando topic: #{topic}"
      # Karafka CLI ou SDK para criar topics
      system("kafka-topics.sh --bootstrap-server #{ENV['KAFKA_URL']} --create --topic #{topic} --partitions 3 --replication-factor 1 2>/dev/null || echo 'Topic já existe'")
    end
  end

  desc "Listar consumer groups e seus offsets"
  task consumer_status: :environment do
    system("kafka-consumer-groups.sh --bootstrap-server #{ENV['KAFKA_URL']} --list")
  end
end

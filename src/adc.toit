
import .driver
import .registers

/// Which conversions the ADC makes. See $Driver.set-adc-conversions.
class AdcConversions:
  /// The channels whose current is converted, bit 0 for channel 1.
  current/int
  /// The channels whose temperature is converted, bit 0 for channel 1.
  temperature/int
  /// The channels whose output voltage is converted, bit 0 for channel 1.
  output-voltage/int
  /// Whether the supply voltage is converted.
  supply-voltage/bool

  constructor --.current --.temperature --.output-voltage --.supply-voltage:

  stringify -> string:
    return "I $(%04b current) T $(%04b temperature) V $(%04b output-voltage) VS $supply-voltage"

/// The decoded form of an ADC burst. See $Driver.read-adc-all.
class AdcReadings:
  /// The 10-bit current conversions, by channel - 1. See $current.
  current-raw/List
  /// The 8-bit temperature conversions, by channel - 1. See $temperature.
  temperature-raw/List
  /// The 8-bit output voltage conversions, by channel - 1. See $output-voltage.
  output-voltage-raw/List
  /// The 10-bit supply voltage conversion. See $supply-voltage.
  supply-voltage-raw/int
  /// The fault byte the last frame of the burst returned. See $Driver.faults.
  faults/int
  /// `RSNS`, in ohms, that $current is decoded with.
  sense-resistor/float
  /// `KSNS` that $current is decoded with.
  sense-ratio/int

  constructor.private_
      .current-raw
      .temperature-raw
      .output-voltage-raw
      .supply-voltage-raw
      .faults
      .sense-resistor
      .sense-ratio:

  /**
  The current through $channel (1-4), in milliamps.

  Only means anything while the channel is on. See $adc-milli-amps.
  */
  current channel/int -> float:
    check-channel_ channel
    return adc-milli-amps current-raw[channel - 1]
        --sense-resistor=sense-resistor
        --sense-ratio=sense-ratio

  /**
  The junction temperature of $channel, in degrees Celsius.

  Means something whether the channel is on or off, unlike $current and
    $output-voltage. See $adc-celsius.
  */
  temperature channel/int -> float:
    check-channel_ channel
    return adc-celsius temperature-raw[channel - 1]

  /** The output voltage of $channel, in volts. See $Driver.read-output-voltage. */
  output-voltage channel/int -> float:
    check-channel_ channel
    return adc-volts output-voltage-raw[channel - 1] --full-scale=ADC-FULL-SCALE-8-BIT

  /** The supply voltage, in volts. See $Driver.read-supply-voltage. */
  supply-voltage -> float:
    return adc-volts supply-voltage-raw --full-scale=ADC-FULL-SCALE-10-BIT

  stringify -> string:
    channels := List CHANNEL-COUNT: | index/int |
      channel := index + 1
      milli-amps := "$(%.0f (current channel))"
      celsius := "$(%.0f (temperature channel))"
      volts := "$(%.1f (output-voltage channel))"
      "CH$channel $milli-amps mA $celsius C $volts V"
    return "VS $(%.1f supply-voltage) V, $(channels.join ", ")"

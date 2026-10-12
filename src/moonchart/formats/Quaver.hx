package moonchart.formats;

import moonchart.backend.FormatData;
import moonchart.backend.Util;
import moonchart.formats.BasicFormat;
import moonchart.formats.fnf.FNFVSlice;
import moonchart.parsers.QuaverParser;
import moonchart.parsers._internal.ZipFile;

using StringTools;

class Quaver extends BasicFormat<QuaverFormat, {}>
{
	public static final QUAVER_SLIDER_VELOCITY:String = "SLIDER_VELOCITY";

	public static function __getFormat():FormatData
	{
		return {
			ID: QUAVER,
			name: "Quaver",
			description: "",
			extension: "qua",
			packedExtension: "qp",
			hasMetaFile: FALSE,
			handler: Quaver
		}
	}

	var parser:QuaverParser;

	public function new(?data:QuaverFormat)
	{
		super({
			timeFormat: MILLISECONDS,
			supportsDiffs: false,
			supportsEvents: true,
			supportsPacks: true
		});
		this.data = data;
		parser = new QuaverParser();
	}

	override function fromBasicFormat(chart:BasicChart, ?diff:FormatDifficulty):Quaver
	{
		var chartResolve = resolveDiffsNotes(chart, diff);
		var chartDiff:String = chartResolve.diffs[0];
		var basicNotes:Array<BasicNote> = chartResolve.notes.get(chartDiff);

		var hitObjects:Array<QuaverHitObject> = Util.makeArray(basicNotes.length);
		var defaultKeySounds:Array<String> = []; // Too lazy to add support for these rn

		for (i in 0...basicNotes.length)
		{
			var note = basicNotes[i];
			Util.setArray(hitObjects, i, {
				StartTime: Std.int(note.time),
				EndTime: note.length > 0 ? Std.int(note.length) : null,
				Lane: note.lane,
				KeySounds: defaultKeySounds
			});
		}

		var basicChanges = chart.meta.bpmChanges;
		var timingPoints:Array<QuaverTimingPoint> = Util.makeArray(basicChanges.length);
		for (i in 0...basicChanges.length)
		{
			var change = basicChanges[i];
			Util.setArray(timingPoints, i, {
				StartTime: Std.int(change.time),
				Bpm: change.bpm
			});
		}

		final extra = chart.meta.extraData;

		final keysMode:String = switch (extra.get(LANES_LENGTH) ?? 4)
		{
			case 4: "Keys4";
			case _: "Keys7";
		}

		var sliders:Array<QuaverSlider> = [];
		for (event in chart.data.events)
		{
			if (event.name == QUAVER_SLIDER_VELOCITY)
			{
				sliders.push({
					StartTime: event.time,
					Multiplier: event.data.multiplier ?? 1
				});
			}
		}

		this.data = {
			AudioFile: extra.get(AUDIO_FILE) ?? "audio.mp3",
			SongPreviewTime: Std.int(extra.get(SONG_PREVIEW_START) ?? 0),
			BackgroundFile: "''",
			MapId: -1,
			MapSetId: -1,
			Mode: keysMode,
			Artist: extra.get(SONG_ARTIST) ?? Moonchart.DEFAULT_ARTIST,
			Source: "''",
			Tags: "''",
			Creator: extra.get(SONG_CHARTER) ?? Moonchart.DEFAULT_CHARTER,
			Description: "Converted with " + Util.version,
			BPMDoesNotAffectScrollVelocity: true,
			InitialScrollVelocity: chart.meta.scrollSpeeds.get(chartDiff) ?? 1.0,
			EditorLayers: [],
			CustomAudioSamples: [],
			SoundEffects: [],
			SliderVelocities: sliders,

			Title: chart.meta.title,
			TimingPoints: timingPoints,
			HitObjects: hitObjects,
			DifficultyName: chartDiff
		}

		return this;
	}

	override function getNotes(?diff:String):Array<BasicNote>
	{
		var hitObjects = data.HitObjects;
		var notes:Array<BasicNote> = Util.makeArray(hitObjects.length);

		for (i in 0...hitObjects.length)
		{
			final hitObject = hitObjects[i];
			final time:Int = (hitObject.StartTime ?? 0);
			final length:Int = (hitObject.EndTime != null) ? hitObject.EndTime - time : 0;

			Util.setArray(notes, i, {
				time: time,
				length: length,
				lane: Std.int(hitObject.Lane - 1),
				type: ""
			});
		}

		return notes;
	}

	override function getEvents():Array<BasicEvent>
	{
		var sliders = data.SliderVelocities;
		var events:Array<BasicEvent> = [];

		for (i in 0...sliders.length)
		{
			var slider = sliders[i];
			var time:Float = slider.StartTime ?? 0.0;
			var multiplier:Null<Float> = slider.Multiplier;

			if (time > 0 && multiplier != null)
			{
				events.push({
					time: time,
					name: QUAVER_SLIDER_VELOCITY,
					data: {
						multiplier: multiplier
					}
				});
			}
		}

		return events;
	}

	function getCommonBPM() 
	{
		if (data.TimingPoints.length == 0) return 0.0;
		if (data.HitObjects.length == 0) return 0.0;

		var lastObject:QuaverHitObject = data.HitObjects[data.HitObjects.length - 1];
		var lastTime:Float =  lastObject.EndTime > 0 ? lastObject.EndTime : lastObject.StartTime;
		var durations:Map<String, Int> = []; // can't do float for some reason lol!!

		for (i in data.TimingPoints.length - 1...0)
		{
			var point = data.TimingPoints[i];
			
			if (point.StartTime > lastTime)
				continue;

			var duration:Int = cast lastTime - (i == 0 ? 0 : point.StartTime);
			lastTime = point.StartTime;

			var bpmString:String = Std.string(point.Bpm);

			if (!durations.exists(bpmString))
				durations.set(bpmString, duration);
			else
				durations.set(bpmString, durations.get(bpmString) + duration);
		}

		var durationsArray:Array<Array<Float>> = [];
		for (i => v in durations)
			durationsArray.push([Std.parseFloat(i), v]);

		durationsArray.sort((a, b) -> Std.int(b[1] - a[1]));

		return durationsArray.length == 0 ? data.TimingPoints[0].Bpm : durationsArray[0][0];
	}

	public function getScrollVelocities():Array<BasicScrollVelocity>
	{
		var vels:Array<BasicScrollVelocity> = [];
		if (data.BPMDoesNotAffectScrollVelocity == true)
		{
			vels.push({
				time: 0,
				multiplier: data.InitialScrollVelocity
			});
			if (data.SliderVelocities.length > 0)
			{
				for (sv in data.SliderVelocities)
				{
					vels.push({
						time: sv.StartTime,
						multiplier: sv.Multiplier
					});
				}
			}
		} else {
			var baseBpm:Float = getCommonBPM();
			
			var currentBpm:Float = data.TimingPoints[0].Bpm;
			var current:Int = 0;
			var currentStartTime:Float = Math.NaN;
			var currentMult:Float = 1;
			var currentAdjustedSV:Float = Math.NaN;
			var initialMult:Float = Math.NaN;

			for (i in 0...data.TimingPoints.length)
			{
				var timingPoint = data.TimingPoints[i];

				var nextHasSameStamp = i + 1 < data.TimingPoints.length && data.TimingPoints[i + 1].StartTime == timingPoint.StartTime;

				while (true)
				{
					if (current >= data.SliderVelocities.length) break;

					var sv = data.SliderVelocities[current];
					if (sv.StartTime > timingPoint.StartTime) break;
					if (nextHasSameStamp && sv.StartTime == timingPoint.StartTime) break;

					if (sv.StartTime < timingPoint.StartTime)
					{
						// The way that osu! handles infinite BPM is more akin to "arbitrarily large SV".
						// We chose the smallest power of two greater than `MAX_MULTIPLIER`
						// from `SVFactor` to make `DenormalizeSVs` more accurate.
						var multiplier = !Math.isFinite(currentBpm) ? 128 : sv.Multiplier * (currentBpm / baseBpm);

						if (Math.isNaN(currentAdjustedSV))
						{
							currentAdjustedSV = multiplier;
							initialMult = multiplier;
						}

						// ReSharper disable once CompareOfFloatsByEqualityOperator
						if (multiplier != currentAdjustedSV)
						{
							vels.push({
								time: sv.StartTime,
								multiplier: multiplier
							});
							//normalizedScrollVelocities.Add(new SliderVelocityInfo {StartTime = sv.StartTime, Multiplier = multiplier});

							currentAdjustedSV = multiplier;
						}
					}

					currentStartTime = sv.StartTime;
					currentMult = sv.Multiplier;
					current++;
				}

				if (Math.isNaN(currentStartTime) || currentStartTime < timingPoint.StartTime)
					currentMult = 1;

				currentBpm = timingPoint.Bpm;

				var multToo = !Math.isFinite(currentBpm) ? 128 : currentMult * (currentBpm / baseBpm);

				if (Math.isNaN(currentAdjustedSV)) {
					currentAdjustedSV = multToo;
					initialMult = multToo;
				}

				if (multToo == currentAdjustedSV) continue;

				vels.push({
					time: timingPoint.StartTime,
					multiplier: multToo
				});

				currentAdjustedSV = multToo;
			}

			for (i in 0...data.SliderVelocities.length)
			{
				current = i;
				var sv = data.SliderVelocities[current];
				var multiplier = !Math.isFinite(currentBpm) ? 128 : sv.Multiplier * (currentBpm / baseBpm);

				if (multiplier == currentAdjustedSV) continue;

				vels.push({
					time: sv.StartTime,
					multiplier: multiplier
				});

				currentAdjustedSV = multiplier;
			}

			if (!Math.isNaN(initialMult))
			{
				vels.push({
					time: 0,
					multiplier: initialMult
				});
			}
		}

		vels.sort((a, b) -> Std.int(a.time - b.time));
		return vels;
	}

	override function getChartMeta():BasicMetaData
	{
		var timingPoints = data.TimingPoints;
		var bpmChanges:Array<BasicBPMChange> = Util.makeArray(timingPoints.length);

		for (i in 0...timingPoints.length)
		{
			var timingPoint = timingPoints[i];
			Util.setArray(bpmChanges, i, {
				time: (timingPoint.StartTime ?? 0),
				bpm: timingPoint.Bpm,
				beatsPerMeasure: 4,
				stepsPerBeat: 4
			});
		}

		final lanesLength:Int = switch (data.Mode)
		{
			case "Keys4": 4;
			case _: 7;
		}

		return {
			title: data.Title,
			bpmChanges: bpmChanges,
			scrollVelocities: getScrollVelocities(), 
			offset: 0.0,
			scrollSpeeds: [diffs[0] => data.InitialScrollVelocity],
			extraData: [
				LANES_LENGTH => lanesLength,
				STRUMLINE_LANES => 1,
				STRUMLINE_KEYS => lanesLength,
				AUDIO_FILE => data.AudioFile,
				SONG_ARTIST => data.Artist,
				SONG_CHARTER => data.Creator
			]
		}
	}

	override function stringify()
	{
		return {
			data: parser.stringify(data),
			meta: null
		}
	}

	override public function fromFile(path:String, ?meta:String, ?diff:FormatDifficulty):Quaver
	{
		return fromQuaver(Util.getText(path), diff);
	}

	public function fromQuaver(data:String, ?diff:FormatDifficulty):Quaver
	{
		this.data = parser.parse(data);
		this.diffs = diff ?? this.data.DifficultyName;
		return this;
	}

	override public function fromPack(path:String, diff:FormatDifficulty):Quaver
	{
		var zip = new ZipFile().openFile(path);
		var chartEntries = zip.filterEntries((entry) -> return entry.fileName.endsWith(".qua"));
		var diffs = diff.resolve();

		for (entry in chartEntries)
		{
			var stringEntry = zip.unzipString(entry);
			var data = parser.parse(stringEntry);

			if (data.DifficultyName == diffs[0])
			{
				return fromQuaver(stringEntry);
				break;
			}
		}

		return this;
	}
}

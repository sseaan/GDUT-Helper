import { common } from '@kit.AbilityKit';
import { TimetableRepository } from '../../data/TimetableRepository';
import { Event, Semester } from '../../domain/model/TimetableModels';
import { IcsEvent, IcsParser } from './IcsParser';

export interface IcsPreview {
  semester: Semester;
  events: IcsEvent[];
  duplicates: number;
  warnings: string[];
}

export class IcsImportService {
  static async preview(context: common.Context, source: string): Promise<IcsPreview> {
    const semester: Semester | null = await TimetableRepository.getCurrentSemester(context);
    if (semester === null) {
      throw new Error('请先设置当前学期');
    }
    const parsed = IcsParser.parse(source);
    const existing: Event[] = await TimetableRepository.listEvents(context, semester.id);
    const externalIds: string[] = existing.map((event: Event) => event.externalId);
    const events: IcsEvent[] = [];
    let duplicates: number = 0;
    for (const event of parsed.events) {
      if (externalIds.indexOf(event.externalId) >= 0) {
        duplicates++;
      } else {
        events.push(event);
      }
    }
    return {
      semester: semester,
      events: events,
      duplicates: duplicates,
      warnings: parsed.warnings
    };
  }

  static async apply(context: common.Context, preview: IcsPreview): Promise<number> {
    const now: number = Date.now();
    for (const source of preview.events) {
      const event: Event = {
        id: '',
        semesterId: preview.semester.id,
        title: source.title,
        startTime: source.startTime,
        endTime: source.endTime,
        allDay: source.allDay,
        location: source.location,
        note: source.note,
        category: source.title.includes('考试') ? 'EXAM' : 'GENERAL',
        source: 'IMPORT',
        externalId: source.externalId,
        createdAt: now,
        updatedAt: now
      };
      await TimetableRepository.upsertEvent(context, event);
    }
    return preview.events.length;
  }
}

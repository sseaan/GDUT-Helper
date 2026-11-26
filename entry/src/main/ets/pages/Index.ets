import {
  HdsNavigation,
  HdsNavigationTitleMode,
  HdsTabs,
  HdsTabsController
} from '@kit.UIDesignKit';
import { MainTabIcon } from '../components/MainTabIcon';
import { AppTheme } from '../common/Theme';
import { ThemeColor } from '../common/ThemeColor';
import { ImmersiveMaterial } from '../common/ImmersiveMaterial';
import { immersiveTitleBar } from '../common/TitleBarOptions';
import { TodayPage } from './today/TodayPage';
import { TimetablePage } from './timetable/TimetablePage';
import { CalendarPage } from './calendar/CalendarPage';
import { CampusPage } from './campus/CampusPage';
import { CampusNewsPage } from './campus/CampusNewsPage';
import { CampusNewsDetailPage } from './campus/CampusNewsDetailPage';
import { LibraryPage } from './library/LibraryPage';
import { LibraryLoginPage } from './library/LibraryLoginPage';
import { ProfilePage } from './profile/ProfilePage';
import { AppearancePage } from './profile/AppearancePage';
import { FeatureSettingsPage } from './profile/FeatureSettingsPage';
import { DataBackupPage } from './profile/DataBackupPage';
import { AboutPage } from './profile/AboutPage';
import { PlaceholderPage } from './common/PlaceholderPage';
import { EmptyClassroomPage } from './classroom/EmptyClassroomPage';
import { GradesPage } from './grades/GradesPage';
import { PhysicalTestPage } from './physical/PhysicalTestPage';
import { TzcsLoginPage } from './physical/TzcsLoginPage';
import { CourseEditPage } from './course/CourseEditPage';
import { SemesterSetupPage } from './semester/SemesterSetupPage';
import { SyncPage } from './sync/SyncPage';
import { EventEditPage } from './event/EventEditPage';
import { AppNavActions } from '../common/AppNavActions';
import { ClockTicker } from '../state/ClockTicker';
import { CourseEditParam, EventEditParam } from '../domain/model/NavParams';

@Entry
@Component
struct Index {
  private stack: NavPathStack = new NavPathStack();
  private tabsController: HdsTabsController = new HdsTabsController();
  @State currentTab: number = 0;
  @StorageLink('themeColorId') @Watch('onThemeColorChange') themeColorId: string = ThemeColor.DEFAULT;
  @Provide('brandColor') brandColor: string = ThemeColor.of(ThemeColor.DEFAULT);
  @Provide('onBrandColor') onBrandColor: string = '#FFFFFF';
  @Provide('brandTextColor') brandTextColor: string = ThemeColor.of(ThemeColor.DEFAULT);
  @StorageLink('immersiveEnabled') immersiveEnabled: boolean = true;
  @StorageLink('materialLevel') materialLevel: number = 10;
  @StorageLink('handednessEnabled') handednessEnabled: boolean = true;
  private navActions: AppNavActions = new AppNavActions();

  private tabTitles: ResourceStr[] = [
    $r('app.string.tab_today'),
    $r('app.string.tab_timetable'),
    $r('app.string.tab_calendar'),
    $r('app.string.tab_campus'),
    $r('app.string.tab_profile')
  ];
  private tabIcons: Resource[] = [
    $r('sys.symbol.clock'),
    $r('sys.symbol.list_bullet_square_fill'),
    $r('sys.symbol.calendar'),
    $r('sys.symbol.square_fill_grid_2x2'),
    $r('sys.symbol.person')
  ];

  private rootTitleBar(): Record<string, Object> {
    return immersiveTitleBar(this.tabTitles[this.currentTab]);
  }

  private openPlaceholder(title: string): void {
    this.stack.pushPathByName('placeholder', title);
  }

  onThemeColorChange(): void {
    this.brandColor = ThemeColor.of(this.themeColorId);
    this.onBrandColor = ThemeColor.onBrand(this.themeColorId);
    this.brandTextColor = ThemeColor.text(this.themeColorId);
  }

  aboutToAppear(): void {
    this.brandColor = ThemeColor.of(this.themeColorId);
    this.onBrandColor = ThemeColor.onBrand(this.themeColorId);
    this.brandTextColor = ThemeColor.text(this.themeColorId);
    ClockTicker.start();
    this.navActions.onOpenSemester = () => {
      this.stack.pushPathByName('semester', null);
    };
    this.navActions.onAddCourse = (semesterId: string) => {
      this.stack.pushPathByName('course-edit', { semesterId: semesterId, courseId: '' } as CourseEditParam);
    };
    this.navActions.onAddMakeup = (semesterId: string, sourceCourseId: string, week: number) => {
      this.stack.pushPathByName('course-edit',
        { semesterId: semesterId, courseId: '', sourceCourseId: sourceCourseId, makeupWeek: week } as CourseEditParam);
    };
    this.navActions.onAddEvent = (semesterId: string, date: string, eventId: string) => {
      this.stack.pushPathByName('event-edit', { semesterId: semesterId, date: date, eventId: eventId } as EventEditParam);
    };
    this.navActions.onOpenSync = () => {
      this.stack.pushPathByName('sync', null);
    };
    this.navActions.onEditCourse = (semesterId: string, courseId: string) => {
      this.stack.pushPathByName('course-edit',
        { semesterId: semesterId, courseId: courseId } as CourseEditParam);
    };
  }

  aboutToDisappear(): void {
    ClockTicker.stop();
  }

  @Builder
  tabIcon(index: number) {
    MainTabIcon({
      title: this.tabTitles[index],
      icon: this.tabIcons[index],
      active: this.currentTab === index
    })
  }

  @Builder
  routeMap(name: string, param: Object) {
    if (name === 'classroom') {
      EmptyClassroomPage({ onOpenSync: () => this.stack.pushPathByName('sync', null) })
    } else if (name === 'appearance') {
      AppearancePage()
    } else if (name === 'features') {
      FeatureSettingsPage()
    } else if (name === 'campus-news') {
      CampusNewsPage({
        onOpenSync: () => this.stack.pushPathByName('sync', null),
        onOpenNewsArticle: (url: string) => this.stack.pushPathByName('news-detail', url)
      })
    } else if (name === 'news-detail') {
      CampusNewsDetailPage({ url: param as string })
    } else if (name === 'library') {
      LibraryPage({ onOpenLogin: () => this.stack.pushPathByName('library-login', null) })
    } else if (name === 'library-login') {
      LibraryLoginPage({ onDone: () => this.stack.pop() })
    } else if (name === 'data-backup') {
      DataBackupPage()
    } else if (name === 'about') {
      AboutPage()
    } else if (name === 'grades') {
      GradesPage({ onOpenSync: () => this.stack.pushPathByName('sync', null) })
    } else if (name === 'physical') {
      PhysicalTestPage({ onOpenLogin: () => this.stack.pushPathByName('tzcs-login', null) })
    } else if (name === 'tzcs-login') {
      TzcsLoginPage({ onDone: () => this.stack.pop() })
    } else if (name === 'sync') {
      SyncPage()
    } else if (name === 'semester') {
      SemesterSetupPage({
        onDone: () => this.stack.pop(),
        onOpenSync: () => this.stack.pushPathByName('sync', null)
      })
    } else if (name === 'event-edit') {
      EventEditPage({
        param: param as EventEditParam,
        onDone: () => this.stack.pop()
      })
    } else if (name === 'course-edit') {
      CourseEditPage({
        param: param as CourseEditParam,
        onDone: () => this.stack.pop()
      })
    } else if (name === 'placeholder') {
      PlaceholderPage({ title: param as string })
    }
  }

  build() {
    HdsNavigation(this.stack) {
      HdsTabs({ controller: this.tabsController }) {
        TabContent() {
          TodayPage({ nav: this.navActions })
        }.tabBar(this.tabIcon(0))

        TabContent() {
          TimetablePage({ nav: this.navActions })
        }.tabBar(this.tabIcon(1))

        TabContent() {
          CalendarPage({ nav: this.navActions })
        }.tabBar(this.tabIcon(2))

        TabContent() {
          CampusPage({
            onOpenClassroom: () => this.stack.pushPathByName('classroom', null),
            onOpenGrades: () => this.stack.pushPathByName('grades', null),
            onOpenPhysical: () => this.stack.pushPathByName('physical', null),
            onOpenPlaceholder: (title: string) => this.openPlaceholder(title),
            onOpenSync: () => this.stack.pushPathByName('sync', null),
            onOpenCampusNews: () => this.stack.pushPathByName('campus-news', null),
            onOpenNewsArticle: (url: string) => this.stack.pushPathByName('news-detail', url),
            onOpenLibrary: () => this.stack.pushPathByName('library', null)
          })
        }.tabBar(this.tabIcon(3))

        TabContent() {
          ProfilePage({
            nav: this.navActions,
            onOpenSync: () => this.navActions.onOpenSync(),
            onOpenFeatures: () => this.stack.pushPathByName('features', null),
            onOpenAppearance: () => this.stack.pushPathByName('appearance', null),
            onOpenDataBackup: () => this.stack.pushPathByName('data-backup', null),
            onOpenAbout: () => this.stack.pushPathByName('about', null)
          })
        }.tabBar(this.tabIcon(4))
      }
      .barOverlap(true)
      .barPosition(BarPosition.End)
      .barMode(BarMode.Fixed)
      .scrollable(false)
      .animationDuration(280)
      .barFloatingStyle({
        barWidth: { smallWidth: 340, mediumWidth: 420, largeWidth: 500 },
        barSideMargin: 12,
        barBottomMargin: AppTheme.TAB_BAR_BOTTOM_MARGIN,
        adaptToHandedness: this.handednessEnabled,
        lightColor: ThemeColor.alpha(this.brandColor, 0.28),
        systemMaterialEffect: {
          materialType: ImmersiveMaterial.type(),
          materialLevel: ImmersiveMaterial.level()
        }
      })
      .onChange((index: number) => {
        this.currentTab = index;
      })
      .width('100%')
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    }
    .titleBar(this.rootTitleBar())
    .titleMode(HdsNavigationTitleMode.MINI)
    .mode(NavigationMode.Stack)
    .navDestination(this.routeMap)
    .hideBackButton(true)
    .backgroundColor(AppTheme.BG)
    .width('100%')
    .height('100%')
  }
}

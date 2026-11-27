import {
  HdsNavigation,
  HdsNavigationTitleMode,
  HdsTabs,
  HdsTabsController
} from '@kit.UIDesignKit';
import { common } from '@kit.AbilityKit';
import { MainTabIcon } from '../components/MainTabIcon';
import { AppTheme } from '../common/Theme';
import { ThemeColor } from '../common/ThemeColor';
import { ImmersiveMaterial } from '../common/ImmersiveMaterial';
import { immersiveTitleBar, titleBarAction } from '../common/TitleBarOptions';
import { ScanService, ScanError } from '../services/scan/ScanService';
import { ScanDispatcher } from '../services/scan/ScanDispatcher';
import { ScanPayload } from '../services/scan/ScanRoute';
import { TodayPage } from './today/TodayPage';
import { TimetablePage } from './timetable/TimetablePage';
import { CalendarPage } from './calendar/CalendarPage';
import { CampusPage } from './campus/CampusPage';
import { CampusNewsPage } from './campus/CampusNewsPage';
import { CampusNewsDetailPage } from './campus/CampusNewsDetailPage';
import { LibraryPage } from './library/LibraryPage';
import { LibraryLoginPage } from './library/LibraryLoginPage';
import { LibrarySearchPage } from './library/LibrarySearchPage';
import { LibraryBookPage } from './library/LibraryBookPage';
import { LibraryBook } from '../services/library/LibraryModels';
import { ProfilePage } from './profile/ProfilePage';
import { AppearancePage } from './profile/AppearancePage';
import { FeatureSettingsPage } from './profile/FeatureSettingsPage';
import { DataBackupPage } from './profile/DataBackupPage';
import { AboutPage } from './profile/AboutPage';
import { MoreServicesPage } from './campus/MoreServicesPage';
import { EmptyClassroomPage } from './classroom/EmptyClassroomPage';
import { SelectionPage } from './selection/SelectionPage';
import { SelectionTaskPage } from './selection/SelectionTaskPage';
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
  private scanBusy: boolean = false;
  /** 「我的」在底栏的索引，扫码按钮只挂在这个 tab 的标题栏上。 */
  private static readonly PROFILE_TAB: number = 4;

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
    const actions: Record<string, Object>[] = [];
    if (this.currentTab === Index.PROFILE_TAB) {
      actions.push(titleBarAction($r('app.string.scan_button_label'),
        $r('sys.symbol.barcode_viewfinder'), () => {
          this.onScan();
        }));
    }
    return immersiveTitleBar(this.tabTitles[this.currentTab], actions);
  }

  private toast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (error) {
      // Toast is optional.
    }
  }

  /** 扫码 → 分类：URL 进浏览器，ISBN 进馆藏检索，其余文本交给弹窗。 */
  private async onScan(): Promise<void> {
    if (this.scanBusy) {
      return;
    }
    this.scanBusy = true;
    try {
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const payload: ScanPayload | null = await ScanService.scan(context);
      if (payload === null) {
        return;
      }
      await ScanDispatcher.dispatch(this.getUIContext(), payload, (isbn: string) => {
        this.stack.pushPathByName('library-search', isbn);
      });
    } catch (error) {
      this.toast(error instanceof ScanError ? error.message : '扫码失败，请重试');
    } finally {
      this.scanBusy = false;
    }
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
      LibraryPage({
        onOpenLogin: () => this.stack.pushPathByName('library-login', null),
        onOpenSearch: (keyword: string) => this.stack.pushPathByName('library-search', keyword)
      })
    } else if (name === 'library-search') {
      LibrarySearchPage({
        initialQuery: param as string,
        onOpenBook: (book: LibraryBook) => this.stack.pushPathByName('library-book', book)
      })
    } else if (name === 'library-book') {
      LibraryBookPage({ book: param as LibraryBook })
    } else if (name === 'library-login') {
      LibraryLoginPage({ onDone: () => this.stack.pop() })
    } else if (name === 'data-backup') {
      DataBackupPage()
    } else if (name === 'about') {
      AboutPage()
    } else if (name === 'more-services') {
      MoreServicesPage({
        onOpenSync: () => this.stack.pushPathByName('sync', null),
        onOpenLibrary: () => this.stack.pushPathByName('library', null),
        onOpenSelection: () => this.stack.pushPathByName('selection', null),
      })
    } else if (name === 'selection') {
      SelectionPage({
        onOpenSync: () => this.stack.pushPathByName('sync', null),
        onOpenTask: () => this.stack.pushPathByName('selection-task', null)
      })
    } else if (name === 'selection-task') {
      SelectionTaskPage()
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
            onOpenMoreServices: () => this.stack.pushPathByName('more-services', null),
            onOpenSync: () => this.stack.pushPathByName('sync', null),
            onOpenCampusNews: () => this.stack.pushPathByName('campus-news', null),
            onOpenNewsArticle: (url: string) => this.stack.pushPathByName('news-detail', url)
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

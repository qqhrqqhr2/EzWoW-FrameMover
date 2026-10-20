local ADDON_NAME, NS = ...

-- Frames strictly excluded to prevent taint in Interface 16001
NS.BLACKLIST_FRAMES = {
    UIParent = true,
    WorldFrame = true,
    CinematicFrame = true,
    MovieFrame = true,
    StaticPopup1 = true,
    StaticPopup2 = true,
    StaticPopup3 = true,
    StaticPopup4 = true,
}

-- Always-loaded standard frames and nested sub-frame trees
NS.STANDARD_FRAMES = {
    AddonList = {},
    BankFrame = {},
    BattlefieldFrame = {},
    CharacterFrame = {
        SubFrames = {
            CompanionFrame = {},
            HonorFrame = {},
            PaperDollFrame = {},
            PetPaperDollFrame = {
                SubFrames = {
                    PetPaperDollFrameCompanionFrame = {},
                },
            },
            PVPFrame = {
                SubFrames = {
                    PVPFrameArena = {},
                    PVPFrameHonor = {},
                    PVPTeam1 = {},
                    PVPTeam2 = {},
                    PVPTeam3 = {},
                },
            },
            ReputationFrame = {
                SubFrames = {
                    ReputationDetailFrame = { Detachable = true },
                    ["ReputationFrame.ReputationDetailFrame"] = { Detachable = true },
                },
            },
            SkillFrame = {},
            TokenFrame = {
                SubFrames = {
                    CurrencyTransferLog = { Detachable = true },
                    TokenFrameContainer = {},
                    TokenFramePopup = { Detachable = true },
                },
            },
        },
    },
    ChatConfigFrame = {},
    ColorPickerFrame = {},
    ContainerFrame1 = {
        SubFrames = {
            ["ContainerFrame1.TitleContainer"] = {},
        },
    },
    ContainerFrameCombinedBags = {
        SubFrames = {
            ["ContainerFrameCombinedBags.TitleContainer"] = {},
        },
    },
    CraftFrame = {},
    DestinyFrame = {},
    DressUpFrame = {
        SubFrames = {
            ["DressUpFrame.CustomSetDetailsPanel"] = { Detachable = true },
            ["DressUpFrame.OutfitDetailsPanel"] = { Detachable = true },
        },
    },
    EUI_ClassicSpellbook = {
        UseSecureCursorDrag = true,
    },
    EUI_ClassicTalents = {},
    FriendsFrame = {
        SubFrames = {
            ["FriendsFrameBattlenetFrame.BroadcastFrame"] = { Detachable = true },
            FriendsFrameFriendsScrollFrame = {},
            ["FriendsFrame.IgnoreListWindow"] = { Detachable = true },
            GuildFrame = {
                SubFrames = {
                    GuildControlPopupFrame = { Detachable = true },
                    GuildEventLogFrame = { Detachable = true },
                    GuildInfoFrame = {
                        Detachable = true,
                        SubFrames = {
                            GuildInfoFrameScrollFrame = {},
                        },
                    },
                },
            },
            RaidInfoFrame = {
                Detachable = true,
                SubFrames = {
                    RaidInfoScrollFrame = {},
                },
            },
        },
    },
    GameMenuFrame = {
        SubFrames = {
            ["GameMenuFrame.Header"] = {},
        },
    },
    GossipFrame = {},
    GroupLootHistoryFrame = {},
    GuildInviteFrame = {},
    GuildRegistrarFrame = {},
    HelpFrame = {},
    InterfaceOptionsFrame = {},
    VideoOptionsFrame = {},
    AudioOptionsFrame = {},
    ItemTextFrame = {},
    LFGDungeonReadyDialog = {},
    LFGInvitePopup = {},
    LFGListInviteDialog = {},
    LFGParentFrame = {
        SubFrames = {
            LFGBrowseFrame = {},
            LFGListingFrame = {},
            LFGWhoListFrame = {},
        },
    },
    LootFrame = {},
    MailFrame = {
        SubFrames = {
            MailFrameInset = { ForceParentage = true },
            OpenMailFrame = {
                Detachable = true,
                ManuallyScaleWithParent = true,
                SubFrames = {
                    OpenMailFrameInset = { ForceParentage = true },
                    OpenMailSender = {},
                },
            },
            SendMailFrame = {},
        },
    },
    MerchantFrame = {},
    ModelPreviewFrame = {},
    PetitionFrame = {},
    PetStableFrame = {},
    PVEFrame = {
        SubFrames = {
            ["LFGListFrame.ApplicationViewer.UnempoweredCover"] = {},
        },
    },
    PVPBannerFrame = {},
    PVPFrame = {
        SubFrames = {
            PVPConquestFrame = {},
            PVPHonorFrame = {},
            WarGamesFrame = {},
        },
    },
    PVPParentFrame = {
        SubFrames = {
            BattlefieldFrame = {},
            PVPFrame = {
                SubFrames = {
                    PVPFrameArena = {},
                    PVPFrameHonor = {},
                    PVPTeam1 = {},
                    PVPTeam2 = {},
                    PVPTeam3 = {},
                },
            },
        },
    },
    QuestFrame = {},
    QuestLogFrame = {},
    QuestLogDetailFrame = {},
    QuestLogPopupDetailFrame = {},
    QuickKeybindFrame = {},
    ReadyCheckFrame = {},
    SettingsPanel = {},
    SocialUIFrame = {},
    SpellBookFrame = {},
    SplashFrame = {},
    StackSplitFrame = {},
    TabardFrame = {},
    TaxiFrame = {},
    TradeFrame = {},
    TradeSkillFrame = {},
    TutorialFrame = {},
    WorldMapFrame = {
        IgnoreSavedPositionWhenMaximized = true,
        SubFrames = {
            QuestMapFrame = {
                SubFrames = {
                    ["QuestMapFrame.DetailsFrame.RewardsFrame"] = {},
                    ["QuestMapFrame.DetailsFrame.ScrollFrame"] = {},
                },
            },
            WorldMapTitleButton = {},
        },
    },
    WorldStateScoreFrame = {},
}

-- Load-On-Demand AddOn frames
NS.LOD_ADDON_FRAMES = {
    Blizzard_AccountStore = {
        AccountStoreFrame = {},
    },
    Blizzard_AchievementUI = {
        AchievementFrame = {
            SubFrames = {
                ["AchievementFrame.Header"] = {},
                AchievementFrameHeader = {},
                AchievementFrameAchievementsContainer = {},
                AchievementFrameCategoriesContainer = {},
            },
        },
        ["AchievementFrame.SearchResults"] = {},
    },
    Blizzard_AlliedRacesUI = {
        AlliedRacesFrame = {},
    },
    Blizzard_AnimaDiversionUI = {
        AnimaDiversionFrame = {
            SubFrames = {
                ["AnimaDiversionFrame.ReinforceProgressFrame"] = {},
                ["AnimaDiversionFrame.ScrollContainer"] = {},
            },
        },
    },
    Blizzard_ArchaeologyUI = {
        ArchaeologyFrame = {},
        ArcheologyDigsiteProgressBar = {},
    },
    Blizzard_ArtifactUI = {
        ArtifactFrame = {},
    },
    Blizzard_AuctionHouseUI = {
        AuctionHouseFrame = {},
    },
    Blizzard_AuctionUI = {
        AuctionFrame = {},
    },
    Blizzard_AzeriteEssenceUI = {
        AzeriteEssenceUI = {},
    },
    Blizzard_AzeriteRespecUI = {
        AzeriteRespecFrame = {},
    },
    Blizzard_AzeriteUI = {
        AzeriteEmpoweredItemUI = {},
    },
    Blizzard_BehavioralMessaging = {
        BehavioralMessagingDetails = {},
    },
    Blizzard_BindingUI = {
        KeyBindingFrame = {},
    },
    Blizzard_BlackMarketUI = {
        BlackMarketFrame = {},
    },
    Blizzard_Calendar = {
        CalendarFrame = {
            SubFrames = {
                CalendarCreateEventFrame = { Detachable = true },
                CalendarViewEventFrame = {
                    Detachable = true,
                    SubFrames = {
                        ["CalendarViewEventFrame.HeaderFrame"] = {},
                    },
                },
                CalendarViewHolidayFrame = { Detachable = true },
            },
        },
    },
    Blizzard_ChallengesUI = {
        ChallengesKeystoneFrame = {},
    },
    Blizzard_Channels = {
        ChannelFrame = {},
    },
    Blizzard_ChromieTimeUI = {
        ChromieTimeFrame = {},
    },
    Blizzard_ClassTalentUI = {
        ClassTalentFrame = {
            SubFrames = {
                ["ClassTalentFrame.TalentsTab.ButtonsParent"] = {},
            },
        },
    },
    Blizzard_ClickBindingUI = {
        ClickBindingFrame = {
            SubFrames = {
                ["ClickBindingFrame.ScrollBox"] = {},
            },
        },
        ["ClickBindingFrame.TutorialFrame"] = {},
    },
    Blizzard_Collections = {
        CollectionsJournal = {
            SubFrames = {
                ["CollectionsJournal.TitleContainer"] = {},
            },
        },
        WardrobeFrame = {},
    },
    Blizzard_Communities = {
        ["ClubFinderGuildFinderFrame.RequestToJoinFrame"] = {},
        CommunitiesFrame = {
            SubFrames = {
                ["CommunitiesFrame.GuildMemberDetailFrame"] = { Detachable = true },
                ["CommunitiesFrame.NotificationSettingsDialog"] = {},
            },
        },
        ["CommunitiesFrame.RecruitmentDialog"] = {},
        CommunitiesGuildLogFrame = {},
        CommunitiesGuildNewsFiltersFrame = {},
        CommunitiesGuildTextEditFrame = {},
        CommunitiesSettingsDialog = {},
    },
    Blizzard_Contribution = {
        ContributionCollectionFrame = {},
    },
    Blizzard_CooldownViewer = {
        CooldownViewerSettings = {},
    },
    Blizzard_CovenantPreviewUI = {
        CovenantPreviewFrame = {},
    },
    Blizzard_CovenantRenown = {
        CovenantRenownFrame = {},
    },
    Blizzard_CovenantSanctum = {
        CovenantSanctumFrame = {},
    },
    Blizzard_CraftUI = {
        CraftFrame = {},
    },
    Blizzard_DeathRecap = {
        DeathRecapFrame = {},
    },
    Blizzard_DelvesCompanionConfiguration = {
        DelvesCompanionAbilityListFrame = {},
        DelvesCompanionConfigurationFrame = {},
    },
    Blizzard_DelvesCompanionConfigurationFrame = {
        DelvesCompanionAbilityListFrame = {},
        DelvesCompanionConfigurationFrame = {},
    },
    Blizzard_DelvesDifficultyPicker = {
        DelvesDifficultyPickerFrame = {},
    },
    Blizzard_EncounterJournal = {
        EncounterJournal = {
            SubFrames = {
                ["EncounterJournal.encounter.info.detailsScroll"] = {},
                ["EncounterJournal.encounter.info.model"] = { NonDraggable = true },
                ["EncounterJournal.encounter.info.overviewScroll"] = {},
                ["EncounterJournal.encounter.instance.LoreScrollingFont.ScrollBox"] = {},
                ["EncounterJournal.instanceSelect.ScrollBox"] = {},
            },
        },
    },
    Blizzard_ExpansionLandingPage = {
        ExpansionLandingPage = {},
    },
    Blizzard_FlightMap = {
        FlightMapFrame = {},
    },
    Blizzard_GarrisonUI = {
        BFAMissionFrame = {},
        CovenantMissionFrame = {
            SubFrames = {
                ["CovenantMissionFrame.FollowerList.MaterialFrame"] = {},
                ["CovenantMissionFrame.MissionTab"] = {},
                ["CovenantMissionFrame.MissionTab.MissionList.MaterialFrame"] = {},
                ["CovenantMissionFrame.MissionTab.MissionPage"] = {},
                ["CovenantMissionFrame.MissionTab.MissionPage.CostFrame"] = {},
                ["CovenantMissionFrame.MissionTab.MissionPage.StartMissionFrame"] = {},
            },
        },
        GarrisonBuildingFrame = {},
        GarrisonCapacitiveDisplayFrame = {},
        GarrisonLandingPage = {},
        GarrisonMissionFrame = {},
        GarrisonMonumentFrame = {},
        GarrisonRecruiterFrame = {},
        GarrisonRecruitSelectFrame = {},
        GarrisonShipyardFrame = {},
        OrderHallMissionFrame = {},
    },
    Blizzard_GenericTraitUI = {
        GenericTraitFrame = {
            SubFrames = {
                ["GenericTraitFrame.ButtonsParent"] = {},
            },
        },
    },
    Blizzard_GroupFinder_VanillaStyle = {
        LFGParentFrame = {
            SubFrames = {
                LFGBrowseFrame = {},
                LFGListingFrame = {},
                LFGWhoListFrame = {},
            },
        },
    },
    Blizzard_GuildBankUI = {
        GuildBankFrame = {},
    },
    Blizzard_GuildControlUI = {
        GuildControlUI = {},
    },
    Blizzard_GuildRename = {
        GuildRenameFrame = {},
    },
    Blizzard_GuildUI = {
        GuildFrame = {},
    },
    Blizzard_HouseEditor = {
        ["HouseEditorFrame.StoragePanel"] = {},
    },
    Blizzard_HouseList = {
        HouseListFrame = {},
    },
    Blizzard_HousingBlueprint = {
        HousingBlueprintContentListFrame = {},
        HousingBlueprintExportFrame = {},
        HousingBlueprintImportFrame = {},
        HousingBlueprintRenameFrame = {},
    },
    Blizzard_HousingBulletinBoard = {
        HousingBulletinBoardFrame = {},
        HousingInviteResidentFrame = {},
        NeighborhoodChangeNameDialog = {},
    },
    Blizzard_HousingCharter = {
        HousingCharterRequestSignatureDialog = {},
    },
    Blizzard_HousingCornerstone = {
        HousingCornerstoneFrame = {},
        HousingCornerstoneHouseInfoFrame = {},
        HousingCornerstonePurchaseFrame = {},
        HousingCornerstoneVisitorFrame = {},
        ImportHouseConfirmationDialog = {},
        MoveHouseConfirmationDialog = {},
    },
    Blizzard_HousingCreateNeighborhood = {
        HousingCreateCharterNeighborhoodConfirmationFrame = {},
        HousingCreateNeighborhoodCharterFrame = {},
    },
    Blizzard_HousingDashboard = {
        HousingDashboardFrame = {
            SubFrames = {
                ["HousingDashboardFrame.HouseInfoContent.DashboardNoHousesFrame"] = {},
            },
        },
    },
    Blizzard_HousingHouseFinder = {
        HouseFinderFrame = {},
    },
    Blizzard_HousingHouseSettings = {
        AbandonHouseConfirmationDialog = {},
        HousingHouseSettingsFrame = {},
    },
    Blizzard_HousingModelPreview = {
        HousingModelPreviewFrame = {},
    },
    Blizzard_InspectUI = {
        InspectFrame = {
            SubFrames = {
                InspectGuildFrame = {},
                InspectHonorFrame = {},
                InspectPaperDollFrame = {},
                InspectPVPFrame = {},
                InspectTalentFrame = {},
            },
        },
    },
    Blizzard_IslandsPartyPoseUI = {
        IslandsPartyPoseFrame = {},
    },
    Blizzard_IslandsQueueUI = {
        IslandsQueueFrame = {},
    },
    Blizzard_ItemAlterationUI = {
        TransmogrifyFrame = {},
    },
    Blizzard_ItemInteractionUI = {
        ItemInteractionFrame = {},
    },
    Blizzard_ItemSocketingUI = {
        ItemSocketingFrame = {},
    },
    Blizzard_ItemUpgradeUI = {
        ItemUpgradeFrame = {},
    },
    Blizzard_LegacySystem = {
        LegacySystemFrame = {
            SubFrames = {
                ["LegacySystemFrame.TreePage.LegacyTreeTraitPanel.ButtonsParent"] = {},
            },
        },
    },
    Blizzard_LookingForGroupUI = {
        LFGParentFrame = {
            SubFrames = {
                LFGBrowseFrame = {},
                LFGListingFrame = {},
                LFGWhoListFrame = {},
            },
        },
    },
    Blizzard_MacroUI = {
        MacroFrame = {},
    },
    Blizzard_MailFrame = {
        MailFrame = {
            SubFrames = {
                MailFrameInset = { ForceParentage = true },
                OpenMailFrame = {
                    Detachable = true,
                    ManuallyScaleWithParent = true,
                    SubFrames = {
                        OpenMailFrameInset = { ForceParentage = true },
                        OpenMailSender = {},
                    },
                },
                SendMailFrame = {},
            },
        },
    },
    Blizzard_MajorFactions = {
        MajorFactionRenownFrame = {},
    },
    Blizzard_MatchCelebrationPartyPoseUI = {
        MatchCelebrationPartyPoseFrame = {},
    },
    Blizzard_ObliterumUI = {
        ObliterumForgeFrame = {},
    },
    Blizzard_OrderHallUI = {
        OrderHallTalentFrame = {},
    },
    Blizzard_PlayerChoice = {
        PlayerChoiceFrame = {
            ForceUseSecureMoveHandle = true,
        },
    },
    Blizzard_PlayerSpells = {
        HeroTalentsSelectionDialog = {},
        ClassTalentLoadoutImportDialog = {},
        ClassTalentLoadoutCreateDialog = {},
        ClassTalentLoadoutEditDialog = {},
        PlayerSpellsFrame = {
            SubFrames = {
                ["PlayerSpellsFrame.TalentsFrame.ButtonsParent"] = {},
            },
        },
    },
    Blizzard_Professions = {
        InspectRecipeFrame = {},
        ProfessionsFrame = {},
        ["ProfessionsFrame.CraftingPage.SchematicForm.QualityDialog"] = {},
        ["ProfessionsFrame.OrdersPage.OrderView.OrderDetails.SchematicForm.QualityDialog"] = {},
    },
    Blizzard_ProfessionsBook = {
        ProfessionsBookFrame = {},
    },
    Blizzard_ProfessionsCustomerOrders = {
        ProfessionsCustomerOrdersFrame = {
            SubFrames = {
                ["ProfessionsCustomerOrdersFrame.Form"] = {},
                ["ProfessionsCustomerOrdersFrame.Form.CurrentListings"] = { Detachable = true },
            },
        },
    },
    Blizzard_PVPMatch = {
        PVPMatchResults = {},
    },
    Blizzard_PVPUI = {
        PVPMatchScoreboard = {},
    },
    Blizzard_QueueStatusFrame = {
        QueueStatusFrame = {},
    },
    Blizzard_ReforgingUI = {
        ReforgingFrame = {
            SubFrames = {
                ["ReforgingFrame.invisButton"] = {},
            },
        },
    },
    Blizzard_RemixArtifactUI = {
        RemixArtifactFrame = {
            SubFrames = {
                ["RemixArtifactFrame.ButtonsParent"] = {},
            },
        },
    },
    Blizzard_RuneforgeUI = {
        RuneforgeFrame = {},
    },
    Blizzard_ScrappingMachineUI = {
        ScrappingMachineFrame = {},
    },
    Blizzard_SocialUI = {
        SocialUIFrame = {},
    },
    Blizzard_Soulbinds = {
        SoulbindViewer = {},
    },
    Blizzard_StableUI = {
        StableFrame = {},
        PetStableFrame = {},
    },
    Blizzard_SubscriptionInterstitialUI = {
        SubscriptionInterstitialFrame = {},
    },
    Blizzard_TalentUI = {
        PlayerTalentFrame = {},
    },
    Blizzard_TimeManager = {
        TimeManagerFrame = {},
    },
    Blizzard_TokenUI = {
        CurrencyTransferMenu = {},
    },
    Blizzard_TorghastLevelPicker = {
        TorghastLevelPickerFrame = {},
    },
    Blizzard_TradeSkillUI = {
        TradeSkillFrame = {},
    },
    Blizzard_TrainerUI = {
        ClassTrainerFrame = {},
    },
    Blizzard_Transmog = {
        TransmogFrame = {},
    },
    Blizzard_VoidStorageUI = {
        VoidStorageFrame = {},
    },
    Blizzard_WarfrontsPartyPoseUI = {
        WarfrontsPartyPoseFrame = {},
    },
    Blizzard_WeeklyRewards = {
        WeeklyRewardsFrame = {},
    },
    Blizzard_WorldMap = {
        WorldMapFrame = {
            IgnoreSavedPositionWhenMaximized = true,
            SubFrames = {
                QuestMapFrame = {
                    SubFrames = {
                        ["QuestMapFrame.DetailsFrame.RewardsFrame"] = {},
                        ["QuestMapFrame.DetailsFrame.ScrollFrame"] = {},
                    },
                },
                WorldMapTitleButton = {},
            },
        },
    },
}

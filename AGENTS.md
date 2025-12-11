#Basic rules

## each subfolder in ./games/ is standalone gamescript, played by backend interpretator  
## never read ./games/*/gamejson/ folder and its content  
## always base your code on avon_template
## next functions are required for interpretator:   
###function DefectButton(defect)  
###function ButtonClick(click)  
###function DefectPixel(defect)   
###function PixelClick(click)   
###function ResumeGame()   
###function PauseGame()   
###function GetStats()   
### They need be at least empty but be declared   
## Each game should have at least such stats:  
local tGameStats = {
    StageLeftDuration = 0, 
    StageTotalDuration = 0, 
    CurrentStars = 0,
    TotalStars = 0,
    CurrentLives = 0,
    TotalLives = 0,
    Players = { -- максимум 6 игроков
        { Score = 0, Lives = 0, Color = CColors.NONE },
        { Score = 0, Lives = 0, Color = CColors.NONE },
        { Score = 0, Lives = 0, Color = CColors.NONE },
        { Score = 0, Lives = 0, Color = CColors.NONE },
        { Score = 0, Lives = 0, Color = CColors.NONE },
        { Score = 0, Lives = 0, Color = CColors.NONE },
    },
    TargetScore = 0,
    StageNum = 0,
    TotalStages = 0,
    TargetColor = CColors.NONE,
    ScoreboardVariant = 0,
}
##  try to use avonlib.lua methods, they are added via submodule:  
###require("avonlib")  

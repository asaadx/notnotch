// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct NotchTaskStrings {
    let title: String
    let empty: String
    let newTask: String
    let placeholder: String
    let add: String
    let save: String
    let cancel: String
    let edit: String
    let delete: String
    let time: String
    let hour: String
    let minute: String
    let markDone: String
    let markNotDone: String
    let limitFormat: String
    let loadFailed: String
    let saveFailed: String
}

extension FeatureStrings {
    static func notchTasks(_ language: AppLanguage) -> NotchTaskStrings {
        switch language {
        case .enUS: return NotchTaskStrings(
            title: "Tasks",
            empty: "Nothing planned yet",
            newTask: "New Task",
            placeholder: "what to do",
            add: "Add",
            save: "Save",
            cancel: "Cancel",
            edit: "Edit",
            delete: "Delete",
            time: "Time",
            hour: "Hour",
            minute: "Minute",
            markDone: "Mark as done",
            markNotDone: "Mark as not done",
            limitFormat: "Up to %d tasks",
            loadFailed: "Tasks could not be read.",
            saveFailed: "Tasks could not be saved.")
        case .ptBR: return NotchTaskStrings(
            title: "Tarefas",
            empty: "Nada planejado ainda",
            newTask: "Nova Tarefa",
            placeholder: "o que fazer",
            add: "Adicionar",
            save: "Salvar",
            cancel: "Cancelar",
            edit: "Editar",
            delete: "Apagar",
            time: "Horário",
            hour: "Hora",
            minute: "Minuto",
            markDone: "Marcar como feita",
            markNotDone: "Marcar como não feita",
            limitFormat: "Até %d tarefas",
            loadFailed: "Não foi possível ler as tarefas.",
            saveFailed: "Não foi possível salvar as tarefas.")
        case .es: return NotchTaskStrings(
            title: "Tareas",
            empty: "Nada planeado todavía",
            newTask: "Nueva tarea",
            placeholder: "qué hacer",
            add: "Añadir",
            save: "Guardar",
            cancel: "Cancelar",
            edit: "Editar",
            delete: "Eliminar",
            time: "Hora",
            hour: "Hora",
            minute: "Minuto",
            markDone: "Marcar como hecha",
            markNotDone: "Marcar como pendiente",
            limitFormat: "Hasta %d tareas",
            loadFailed: "No se pudieron leer las tareas.",
            saveFailed: "No se pudieron guardar las tareas.")
        case .sk: return NotchTaskStrings(
            title: "Úlohy",
            empty: "Zatiaľ nič naplánované",
            newTask: "Nová úloha",
            placeholder: "čo urobiť",
            add: "Pridať",
            save: "Uložiť",
            cancel: "Zrušiť",
            edit: "Upraviť",
            delete: "Vymazať",
            time: "Čas",
            hour: "Hodina",
            minute: "Minúta",
            markDone: "Označiť ako hotové",
            markNotDone: "Označiť ako nehotové",
            limitFormat: "Najviac %d úloh",
            loadFailed: "Úlohy sa nepodarilo načítať.",
            saveFailed: "Úlohy sa nepodarilo uložiť.")
        case .de: return NotchTaskStrings(
            title: "Aufgaben",
            empty: "Noch nichts geplant",
            newTask: "Neue Aufgabe",
            placeholder: "was zu tun ist",
            add: "Hinzufügen",
            save: "Sichern",
            cancel: "Abbrechen",
            edit: "Bearbeiten",
            delete: "Löschen",
            time: "Uhrzeit",
            hour: "Stunde",
            minute: "Minute",
            markDone: "Als erledigt markieren",
            markNotDone: "Als offen markieren",
            limitFormat: "Bis zu %d Aufgaben",
            loadFailed: "Die Aufgaben konnten nicht gelesen werden.",
            saveFailed: "Die Aufgaben konnten nicht gesichert werden.")
        case .fr: return NotchTaskStrings(
            title: "Tâches",
            empty: "Rien de prévu pour l’instant",
            newTask: "Nouvelle tâche",
            placeholder: "quoi faire",
            add: "Ajouter",
            save: "Enregistrer",
            cancel: "Annuler",
            edit: "Modifier",
            delete: "Supprimer",
            time: "Heure",
            hour: "Heure",
            minute: "Minute",
            markDone: "Marquer comme faite",
            markNotDone: "Marquer comme à faire",
            limitFormat: "Jusqu’à %d tâches",
            loadFailed: "Impossible de lire les tâches.",
            saveFailed: "Impossible d’enregistrer les tâches.")
        case .it: return NotchTaskStrings(
            title: "Attività",
            empty: "Ancora niente in programma",
            newTask: "Nuova attività",
            placeholder: "cosa fare",
            add: "Aggiungi",
            save: "Salva",
            cancel: "Annulla",
            edit: "Modifica",
            delete: "Elimina",
            time: "Ora",
            hour: "Ora",
            minute: "Minuto",
            markDone: "Segna come fatta",
            markNotDone: "Segna come da fare",
            limitFormat: "Fino a %d attività",
            loadFailed: "Impossibile leggere le attività.",
            saveFailed: "Impossibile salvare le attività.")
        case .ru: return NotchTaskStrings(
            title: "Задачи",
            empty: "Пока ничего не запланировано",
            newTask: "Новая задача",
            placeholder: "что сделать",
            add: "Добавить",
            save: "Сохранить",
            cancel: "Отменить",
            edit: "Изменить",
            delete: "Удалить",
            time: "Время",
            hour: "Час",
            minute: "Минута",
            markDone: "Отметить как выполненную",
            markNotDone: "Отметить как невыполненную",
            limitFormat: "Не более %d задач",
            loadFailed: "Не удалось прочитать задачи.",
            saveFailed: "Не удалось сохранить задачи.")
        case .tr: return NotchTaskStrings(
            title: "Görevler",
            empty: "Henüz plan yok",
            newTask: "Yeni Görev",
            placeholder: "yapılacak",
            add: "Ekle",
            save: "Kaydet",
            cancel: "Vazgeç",
            edit: "Düzenle",
            delete: "Sil",
            time: "Saat",
            hour: "Saat",
            minute: "Dakika",
            markDone: "Yapıldı olarak işaretle",
            markNotDone: "Yapılmadı olarak işaretle",
            limitFormat: "En fazla %d görev",
            loadFailed: "Görevler okunamadı.",
            saveFailed: "Görevler kaydedilemedi.")
        case .ja: return NotchTaskStrings(
            title: "タスク",
            empty: "まだ予定はありません",
            newTask: "新規タスク",
            placeholder: "やること",
            add: "追加",
            save: "保存",
            cancel: "キャンセル",
            edit: "編集",
            delete: "削除",
            time: "時刻",
            hour: "時",
            minute: "分",
            markDone: "完了にする",
            markNotDone: "未完了にする",
            limitFormat: "最大%d件",
            loadFailed: "タスクを読み込めませんでした。",
            saveFailed: "タスクを保存できませんでした。")
        case .ko: return NotchTaskStrings(
            title: "할 일",
            empty: "아직 계획이 없습니다",
            newTask: "새로운 할 일",
            placeholder: "할 일",
            add: "추가",
            save: "저장",
            cancel: "취소",
            edit: "편집",
            delete: "삭제",
            time: "시간",
            hour: "시",
            minute: "분",
            markDone: "완료로 표시",
            markNotDone: "미완료로 표시",
            limitFormat: "최대 %d개",
            loadFailed: "할 일을 읽을 수 없습니다.",
            saveFailed: "할 일을 저장할 수 없습니다.")
        case .uk: return NotchTaskStrings(
            title: "Завдання",
            empty: "Поки нічого не заплановано",
            newTask: "Нове завдання",
            placeholder: "що зробити",
            add: "Додати",
            save: "Зберегти",
            cancel: "Скасувати",
            edit: "Змінити",
            delete: "Видалити",
            time: "Час",
            hour: "Година",
            minute: "Хвилина",
            markDone: "Позначити як виконане",
            markNotDone: "Позначити як невиконане",
            limitFormat: "Не більше %d завдань",
            loadFailed: "Не вдалося прочитати завдання.",
            saveFailed: "Не вдалося зберегти завдання.")
        case .zhHans: return NotchTaskStrings(
            title: "任务",
            empty: "暂无计划",
            newTask: "新任务",
            placeholder: "要做的事",
            add: "添加",
            save: "存储",
            cancel: "取消",
            edit: "编辑",
            delete: "删除",
            time: "时间",
            hour: "时",
            minute: "分",
            markDone: "标记为已完成",
            markNotDone: "标记为未完成",
            limitFormat: "最多 %d 项",
            loadFailed: "无法读取任务。",
            saveFailed: "无法存储任务。")
        case .zhTW: return NotchTaskStrings(
            title: "任務",
            empty: "尚無計畫",
            newTask: "新任務",
            placeholder: "要做的事",
            add: "加入",
            save: "儲存",
            cancel: "取消",
            edit: "編輯",
            delete: "刪除",
            time: "時間",
            hour: "時",
            minute: "分",
            markDone: "標示為已完成",
            markNotDone: "標示為未完成",
            limitFormat: "最多 %d 項",
            loadFailed: "無法讀取任務。",
            saveFailed: "無法儲存任務。")
        case .zhHK: return NotchTaskStrings(
            title: "任務",
            empty: "尚未有計劃",
            newTask: "新任務",
            placeholder: "要做的事",
            add: "加入",
            save: "儲存",
            cancel: "取消",
            edit: "編輯",
            delete: "刪除",
            time: "時間",
            hour: "時",
            minute: "分",
            markDone: "標示為已完成",
            markNotDone: "標示為未完成",
            limitFormat: "最多 %d 項",
            loadFailed: "無法讀取任務。",
            saveFailed: "無法儲存任務。")
        }
    }
}

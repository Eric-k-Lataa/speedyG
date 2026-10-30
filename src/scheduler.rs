// src/scheduler.rs
use crate::state_machine::{new_job, Job, JobEvent, JobState};
use serde::{Deserialize, Serialize};
use std::collections::VecDeque;

use tracing::{info, warn};

/// Administrador de la cola de tareas y envio (?) hacia el Executor
#[derive(Debug, Serialize, Deserialize)]
pub struct Scheduler {
    next_id: u32,
    queue: VecDeque<Job>,
    history: Vec<Job>,
    queue_cap: usize,
}

impl Default for Scheduler {
    fn default() -> Self {
        Self::new()
    }
}

impl Scheduler {
    pub fn new() -> Self {
        Self {
            next_id: 1,
            queue: VecDeque::new(),
            history: Vec::new(),
            queue_cap: crate::config::DEFAULT_QUEUE_CAP,
        }
    }
    pub fn set_queue_cap(&mut self, capacity: usize) {
        self.queue_cap = capacity;
    }

    ///Reconstruye scheduler con datos leidos del disco para la persistencia.
    pub fn from_parts(next_id: u32, queue: VecDeque<Job>, history: Vec<Job>) -> Self {
        Self {
            next_id,
            queue,
            history,
            queue_cap: crate::config::DEFAULT_QUEUE_CAP,
        }
    }

    ///Siguiente ID asignado para no reutilizar tras el reinicio.
    pub fn next_id(&self) -> u32 {
        self.next_id
    }

    /// Encola un nuevo comando si hay espacio disponible
    pub fn add_job(&mut self, program: String, args: Vec<String>) -> Result<&Job, String> {
        let waiting = self
            .queue
            .iter()
            .filter(|job| matches!(job.get_state(), JobState::Queued))
            .count();
        if waiting >= self.queue_cap {
            let error = format!("Error al enviar '{}': la cola está llena (capacidad: {}). Espera a que se libere un espacio", program, self.queue_cap);
            warn!("{}", error);
            return Err(error);
        }
        let job = new_job(self.next_id, program, args, true);
        self.next_id += 1;
        self.queue.push_back(job);

        Ok(self.queue.back().unwrap())
    }

    /// Busca un Job por ID tanto en la cola activa como en el historial
    pub fn get_job(&self, id: u32) -> Option<&Job> {
        self.queue
            .iter()
            .chain(self.history.iter())
            .find(|j| j.get_id() == id)
    }

    /// Cancela un Job si aún está en la cola o ejecución
    pub fn cancel_job(&mut self, id: u32) -> bool {
        if let Some(pos) = self.queue.iter().position(|j| j.get_id() == id) {
            let mut job = self.queue.remove(pos).unwrap();
            job.transition(JobEvent::Cancel);
            self.history.push(job);
            true
        } else {
            false
        }
    }

    /// Marca un proceso como running (para cuando se llaman asincronos mas que nada)
    pub fn start_job(&mut self, id: u32) -> bool {
        if let Some(job) = self.queue.iter_mut().find(|j| j.get_id() == id) {
            job.transition(JobEvent::CapacityAvailable);
            true
        } else {
            false
        }
    }

    /// Completa la ejecución de un trabajo y actualiza la FSM
    pub fn complete_job(&mut self, id: u32, exit_code: i32) -> bool {
        if let Some(pos) = self.queue.iter().position(|j| j.get_id() == id) {
            let mut job = self.queue.remove(pos).unwrap();
            // Solo enviamos Completed, el Job ya pasó a Running mediante start_job
            job.transition(JobEvent::Completed(exit_code));
            self.history.push(job);
            true
        } else {
            false
        }
    }

    /// Retorna una lista de referencias con las tareas actualmente en cola
    pub fn pending_jobs(&self) -> Vec<&Job> {
        self.queue.iter().collect()
    }

    /// Retorna una lista de referencias con el historial de tareas finalizadas
    pub fn history_jobs(&self) -> Vec<&Job> {
        self.history.iter().collect()
    }

    ///Recuperacion
    pub fn recuperar_tras_reinicio(&mut self) -> Vec<u32> {
        let mut por_relanzar = Vec::new();
        let mut restantes = VecDeque::new();

        while let Some(mut job) = self.queue.pop_front() {
            job.transition(JobEvent::ServiceRestarted);

            match job.get_state() {
                JobState::Queued => {
                    info!(
                        "Recuperación: Job #{} sigue en cola; se relanzará",
                        job.get_id()
                    );
                    por_relanzar.push(job.get_id());
                    restantes.push_back(job);
                }

                JobState::Interrupted => {
                    warn!(
                        "Recuperación: Job #{} estaba Running; se marca Interrupted",
                        job.get_id()
                    );
                    self.history.push(job);
                }

                otro => {
                    warn!(
                        "Recuperación: Job #{} en cola con estado {:?}; se mueve al historial",
                        job.get_id(),
                        otro
                    );
                    self.history.push(job);
                }
            }
        }

        self.queue = restantes;
        por_relanzar
    }
}
